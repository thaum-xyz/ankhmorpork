# vod-arr

Replaces the `multimedia` namespace, which had drifted to the point where nobody
could say what was configured in it. Everything that matters is either declared
here or reproducible from a blank config.

| Component     | Role                                | Host                    |
| ------------- | ----------------------------------- | ----------------------- |
| prowlarr      | indexer manager, feeds the others   | `prowlarr`              |
| sonarr        | TV                                  | `sonarr`                |
| radarr        | movies                              | `radarr`                |
| bazarr        | subtitles for both                  | `bazarr`                |
| qbittorrent   | download client, behind NordVPN     | `downloader`            |
| seerr         | requests, backed by Plex            | `seek.krupa.net.pl`     |
| flaresolverr  | Cloudflare solver for prowlarr      | cluster-internal only   |
| recyclarr     | nightly TRaSH profile sync (CronJob)| —                       |

All hosts are `<name>.ankhmorpork.thaum.xyz` on the `private` ingress class,
except seerr: it is `seek.krupa.net.pl` on `public` plus a `cloudflare` twin, so
people outside the house can request things. Both ingresses are needed —
external-dns publishes only the tunnel CNAME from the cloudflare one, and
`*.cfargotunnel.com` resolves nowhere internally, so the internal resolver would
hand out a name with no address.

Access control there is Seerr's own Plex sign-in. It has no OIDC of its own
(upstream issue #183 and PR #2715 are still open), so there is no pocket-id in
front; anyone with a Plex account on the server gets in.

## Images

`ghcr.io/home-operations/*` rather than linuxserver. Same upstream binaries, but
no s6 and no PUID/PGID: the process runs as whatever UID the pod securityContext
names, so every app container here can be `runAsNonRoot` with all capabilities
dropped. UID 1000 is kept because that is what the NFS exports already accept.

gluetun is the one exception — it has to be root to create the tunnel and program
iptables, so the qBittorrent pod sets no pod-level `runAsNonRoot` and each of the
other containers names its own UID instead.

Seerr is the renamed Jellyseerr (`seerr-team/seerr`), a major version on from the
last release carrying the old name.

## The VPN kill switch

`qbittorrent` is a three-container pod. gluetun is the only one with
`NET_ADMIN`; it owns the pod's network namespace and its firewall drops
everything that is not the tunnel or one of `FIREWALL_OUTBOUND_SUBNETS` (pod
CIDR, service CIDR, node subnet — where kubelet probes and Traefik arrive from).
qBittorrent therefore has no route to the internet except through the tunnel,
and none at all while the tunnel is down. The guarantee is a property of the
netns, not of the client behaving itself.

Two details that are easy to get wrong and are deliberate here:

- `FIREWALL_INPUT_PORTS` is **unset**. It opens the listener on the tunnel
  interface as well, which would publish the WebUI to the VPN network.
- `dnsPolicy: None` with nameserver `127.0.0.1` points both containers at
  gluetun's DNS-over-TLS resolver. Left on cluster DNS, qBittorrent would
  resolve trackers through CoreDNS and out of the node — a plaintext record of
  every download, outside the tunnel the rest of the traffic uses.

NordVPN offers no port forwarding, so there are no inbound peers. Every indexer
in use is a public tracker with no ratio requirement, so this costs nothing; it
would matter immediately on a private tracker.

### Moving to WireGuard

OpenVPN is used because the service credentials already in Doppler work as-is.
WireGuard is faster and needs a NordLynx private key:

```bash
curl -s -u token:<NORDVPN_TOKEN> https://api.nordvpn.com/v1/users/services/credentials
```

Put `nordlynx_private_key` in Doppler, add it to `vpn-credentials.yaml` as
`WIREGUARD_PRIVATE_KEY`, and set `VPN_TYPE: wireguard` in `config.yaml`.

## Storage, and why imports are copies

Three NFS exports, mounted at identical paths in every component that needs
them, so path mappings between the *arrs and Bazarr are the identity:

| Claim           | Export                          | Mounted at       |
| --------------- | ------------------------------- | ---------------- |
| `vod-tv`        | `/var/nfs/shared/tvshows`       | `/media/tv`      |
| `vod-movies`    | `/var/nfs/shared/movies`        | `/media/movies`  |
| `vod-downloads` | `/var/nfs/shared/transmission`  | `/downloads`     |

On the UNAS these are three separate btrfs subvolumes, so a hardlink across them
fails with `EXDEV`. Sonarr and Radarr fall back to copying, which means an
import writes the file a second time and a seeding torrent occupies disk twice.

Fixing that means one share holding both `torrents/` and `media/`. It is cheap
to do — cross-subvolume **reflink** works on this filesystem, so consolidating
the existing ~5.7 TB is a metadata operation, not a copy — but it also moves the
libraries out from under Plex and Jellyfin, so it was deliberately left out of
this change.

Until then, keep qBittorrent's seeding limits (ratio 2 / 7 days, already seeded
into `qBittorrent.conf`) and leave "Remove Completed Downloads" on in both
*arrs, or `/downloads` grows without bound.

### Config volumes

`piraeus-r2-roaming`: two DRBD replicas, but the Pod is not pinned to them. It
may schedule onto any satellite node and attach diskless, and
`DrbdOptions/auto-diskful: 5` promotes an attachment that has been Primary for
five minutes into a local replica while the controller drops the surplus one, so
the data follows the Pod.

I/O is remote until that conversion completes, which is why the class is capped
at 32Gi by the `validate-roaming-volume-size` policy. Every volume here is 2Gi.

Not `piraeus-r2`: it pins the Pod to the two nodes holding its replicas, which is
the right trade for something latency-sensitive like plex's `/config`, but these
are small single-replica apps where being able to land anywhere is worth more
than local I/O. Note both classes format xfs rather than ext4, which matters only
in that xfs cannot be shrunk.

The CNPG clusters stay on the chart's `lvm-thin`: they have their own replication
and barman backups, so DRBD underneath would be a second copy of a guarantee
Postgres already gives.

## Configuration that is declared

The `postgres-setup` init container rewrites `config.xml` on every start. It
sets the Postgres connection, turns the built-in login **off**
(`AuthenticationMethod: External` — the private ingress is the trust boundary,
and a password nobody has is how the old namespace became unauditable), and
pins the API key from Doppler when the entry exists.

A declared API key is what lets Prowlarr, Bazarr and Recyclarr be configured
against these apps without reading a generated value back out of a database.

### Doppler entries

Reused: `VPN_USERNAME`, `VPN_PASSWORD`, `{SONARR,RADARR,PROWLARR}_DB_ADMIN_PASS`,
`{SONARR,RADARR,PROWLARR}_DB_PASS`, `POSTGRES_S3_{ACCESS,SECRET}_KEY`.

New, and optional — absent, each app generates its own key and only the
automated integrations suffer: `SONARR_API_KEY`, `RADARR_API_KEY`,
`PROWLARR_API_KEY`.

## Configuration that is not

These live in each app's database and have to be clicked once:

1. **Prowlarr** — add indexers; add Sonarr and Radarr under Settings → Apps
   (`http://sonarr:8989`, `http://radarr:7878`, sync level Full Sync); add
   FlareSolverr as an indexer proxy at `http://flaresolverr:8191`.
2. **Sonarr / Radarr** — root folder `/media/tv` and `/media/movies`; download
   client qBittorrent at host `qbittorrent` port `8080` with **no credentials**
   (the WebUI trusts the pod CIDR), category `tv` and `movies` respectively;
   Remove Completed Downloads on.
3. **Bazarr** — connect both *arrs by API key, mind that its paths already
   match, then pick subtitle providers.
4. **Seerr** — sign in with Plex, select libraries, connect Sonarr/Radarr.
   `applicationUrl` and `network.trustProxy` are seeded on first run: without
   trustProxy the app reads the proxy's address as every client's, which breaks
   rate limiting and the links in its notifications.

Recyclarr syncs the quality profiles and custom formats nightly, so profile
choices belong in `recyclarr/config.yaml`, not in the UI.

## Cutover from multimedia

`k8s/flux/apps` has `prune: false`, so deleting the old files does not remove
anything from the cluster — see the app-removal order. The old and new stacks
claim the same ingress hostnames, so the teardown has to happen first:

```bash
kubectl delete kustomization multimedia -n flux-system
kubectl wait --for=delete ns/multimedia --timeout=10m
flux reconcile kustomization apps --with-source
```

The old PVs are `Retain`, so no media is at risk. Nothing in the old namespace
was worth migrating: every indexer was public, and both root folders were
`/multimedia`.
