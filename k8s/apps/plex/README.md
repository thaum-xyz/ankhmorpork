# plex

Plex Media Server, in its own namespace, reading the same NFS exports jellyfin
and multimedia already use.

## Claiming the server

The server starts unclaimed. A claim token from <https://plex.tv/claim> is valid
for four minutes, so it is created by hand rather than kept in Doppler:

```bash
kubectl -n plex create secret generic plex-claim --from-literal=PLEX_CLAIM=claim-xxxxxxxxxxxxxxxxxxxx
kubectl -n plex rollout restart statefulset/plex
```

`envFrom` marks the Secret optional, so the pod runs with or without it. The
exchange is skipped once `PlexOnlineToken` is set, so a spent token is inert,
but delete the Secret anyway — it will be the first suspect when a later reclaim
silently fails.

Libraries point at `/data/movies` and `/data/tv`.

## Settings that have no manifest

`plexinc/pms-docker` maps exactly two preferences from the environment
(`ADVERTISE_IP` → `customConnections`, `ALLOWED_NETWORKS` → `allowedNetworks`).
Everything else is UI-only. After claiming, set under Settings → Network:

- **LAN Networks** → `192.168.0.0/16,10.42.0.0/16,100.64.0.0/10`. This, not
  `ALLOWED_NETWORKS`, is what decides whether a client is billed as local or
  throttled to the remote-quality limit. `10.42.0.0/16` covers traffic arriving
  through the ingress, which carries traefik's pod IP. `100.64.0.0/10` covers
  tailnet clients reaching the Service directly — see the SNAT note below for
  why their real address survives.
- **Secure connections** → `Preferred`, never `Required`. Traefik terminates
  TLS and speaks plain HTTP to 32400, so `Required` breaks the ingress path.

`ALLOWED_NETWORKS` is deliberately unset: it is an *unauthenticated* access
allowlist, not a LAN hint, and any entry covering the pod CIDR would hand
unauthenticated access to everything that can reach the ingress. Plex's own
docs recommend setting it only on a server that is never signed in.

## Caveats

### The ingress is LAN-only, and is not remote access

`ingressClassName: private` puts `vod.krupa.net.pl` on the internal traefik at
`192.168.50.130`, which external-dns publishes to UniFi's resolver. Off-LAN the
name still *resolves* — the `*.krupa.net.pl` wildcard CNAME sends it to
Cloudflare — but cloudflared has no route for it, because there is no
`ingress-cloudflare.yaml` here. So it answers on the LAN and errors everywhere
else.

Reverse-proxying Plex at the *root* of a hostname is supported: that is what
`customConnections` exists for, traefik handles the WebSocket upgrade the web UI
needs, and it preserves the Host header. A sub*path* (`/plex`) is the
arrangement Plex has never handled cleanly; this is not that.

### Remote access goes over the tailnet

The site sits behind two layers of NAT and only the inner router is ours, so no
inbound port-forward can reach 32400, and Plex's own Remote Access — which wants
to punch a UPnP/NAT-PMP hole — cannot work from inside cluster networking. The
fallback is Plex's relay: outbound-only, zero configuration, and capped at
2 Mbps on a Plex Pass, which is roughly SD.

Instead, remote clients come in over Tailscale. Every node already runs
`tailscaled`; `metal/30_tailscale.yml` owns the advertised subnet routes. Both
entries in `ADVERTISE_IP` are handed to clients, which try them in turn:

- `https://vod.krupa.net.pl:443/` — through the private traefik at
  `192.168.50.130`. This is the path that always works: private-traefik runs a
  pod on **both** beelinks, so whichever one holds the primary subnet route
  satisfies its `externalTrafficPolicy: Local`, and traefik then reaches Plex
  in-cluster wherever it is. Needs Tailscale split DNS for `krupa.net.pl`
  pointed at the UniFi resolver, or the name will not resolve on the tailnet.
- `http://192.168.50.135:32400/` — straight at the LoadBalancer VIP. One hop
  shorter, but Plex is a single pod, so `externalTrafficPolicy: Local` means
  cilium only accepts this on the node actually running it. Treat it as the LAN
  fast path that sometimes also serves the tailnet, not as the remote path.

That the VIP is reachable through a tunnel at all is worth knowing: cilium has
`tailscale0` in its managed device list, so BPF load-balancing runs on packets
arriving from the tailnet exactly as it does on `bond0` — including the traffic
policy. Measured on 2026-08-28 with beelink01 as the primary subnet router and a
one-pod LoadBalancer moved between nodes:

| pod placement | `etp: Local` | `etp: Cluster` |
| --- | --- | --- |
| on the router node | 200 | 200 |
| on the other node  | no route | 200 |

So the VIP entry is dead weight whenever Plex and the primary subnet router are
not the same node. Plex probes its candidate URLs and settles on one that
answers, so this costs a little connection-setup time rather than breaking
anything — the ingress entry above is what carries it. Note that adding a second
subnet router does **not** fix this: tailscale elects one primary per route, so
the mismatch just moves. Pinning Plex to the router node would, at the cost of
tying media placement to VPN routing.

Tailnet traffic is **not** SNAT'd, despite `NoSNAT=false` on the router.
Tailscale implements that masquerade as an iptables rule in `ts-postrouting`,
and cilium's BPF datapath (`bpf.hostLegacyRouting: false`, netkit, BPF
masquerade) delivers the packet to the pod without traversing netfilter, so the
rule never runs. Verified by the source address in cilium's own drop trace: the
pod was replying straight to `100.104.66.107`, not to a node address.

The practical effect is that a client reaching the Service directly keeps its
real `100.x` tailnet address, which is why `100.64.0.0/10` belongs in **LAN
Networks**. Through the ingress, traefik terminates the connection and Plex sees
`10.42.x` instead, with the tailnet address surviving only in
`X-Forwarded-For`.

### No video touches Cloudflare

Worth stating because the repo's own pattern invites the mistake: every publicly
reachable app here pairs its `public` Ingress with an `ingress-cloudflare.yaml`
on the `cloudflare` class. Plex has no such file, so cloudflared holds no route
for `vod.krupa.net.pl` and the Cloudflare edge answers it with a bare 404
(verified 2026-08-28 against `188.114.97.11`; `papers.krupa.net.pl`, which does
have one, returns 302 from the same edge). Streaming runs
client → tailnet → beelink01 → private traefik → pod, and never leaves
WireGuard and the LAN.

Cloudflare is in the picture twice, both on the DNS plane and neither carrying
bytes: it is authoritative for `krupa.net.pl`, and `letsencrypt-prod` solves
DNS-01 through its API.

Adding an `ingress-cloudflare.yaml` here is what would push video through the
CDN, so don't, however much it looks like the missing half of the pattern.
Plex has no separate media port — direct play is a range `GET` on
`/library/parts/...` and a transcode is HLS under `/video/:/transcode/...`,
both on 32400 alongside the web app and the metadata API. A client picks one
connection URI and uses it for the whole session, so a tunnelled hostname
carries the media, not just the UI. Path-restricting the tunnel to `/web` does
not help: it breaks playback rather than diverting it elsewhere.

Cloudflare is explicit that this is not allowed, and specifically that Tunnel is
not a loophole — "Cloudflare Tunnel public hostname routes proxy traffic through
Cloudflare. On Free, Pro, and Business plans, this traffic is subject to the
terms described on this page." Private network routes are exempt, but those need
WARP on every client, which is what the tailnet already does. The sanctioned
escape is a grey-clouded (DNS-only) record, which needs a reachable origin —
and behind this site's double NAT there isn't one.
https://developers.cloudflare.com/fundamentals/reference/policies-compliances/delivering-videos-with-cloudflare/

### Traffic policy

`externalTrafficPolicy: Cluster`, and the earlier reasoning for `Local` was
wrong. `Local` only accepts traffic on the node actually holding the pod, so
over the tailnet it works solely when the subnet router and plex land on the
same beelink. Measured with a one-pod LoadBalancer moved between nodes:

| pod placement | `etp: Local` | `etp: Cluster` |
| --- | --- | --- |
| on the subnet router | 200 | 200 |
| on the other node | no route | 200 |

That is what broke AppleTV playback while the UI kept working — the UI came
through the ingress, where traefik has a pod on both beelinks and so always
satisfied `Local`, while playback went to the advertised VIP and found nothing.
The argument for `Local` had been that `Cluster` hides the client IP; it does,
but the SNAT'd address is a node IP in `192.168.50.0/24`, which is inside the
**LAN Networks** value above, so clients still count as local. The only real
loss is that plex cannot tell a LAN client from a tailnet one.

Two Services on purpose: `plex` is a ClusterIP serving only as the ingress
backend, and `plex-lb` carries the LoadBalancer VIP for direct clients.

`ADVERTISE_IP` is tied to `plex-lb`'s `loadBalancerIP`; changing one without the
other leaves clients falling back to the plex.tv relay. Do not swap the VIP for
the node address via the downward API — the config volume has two replicas, so
the pod can move and the advertisement would move with it, while plex.tv goes on
handing clients the address it cached.

### First-run environment variables re-apply on every start

`40-plex-first-run` short-circuits on `/.firstRunComplete`, which lives on the
container's ephemeral root filesystem rather than in `/config`. So a new
container is always a "first run": `PLEX_UID`, `PLEX_GID` and `ADVERTISE_IP` are
genuinely declarative here, and editing them in git takes effect on restart.

### Hardware transcoding

`gpu.intel.com/i915: "1"` is what puts `/dev/dri` in the container; the image's
own `45-plex-hw-transcode-and-connected-tuner` init script then adds the `plex`
user to the render group, so no `supplementalGroups` are needed. Transcoding
still has to be switched on under Settings → Transcoder, and it needs an active
Plex Pass.

### Storage

`/config` is `piraeus-r2` — DRBD with two replicas and
`allowRemoteVolumeAccess: false`, so the pod must run where a replica lives but
can use either. In practice that is beelink01 or beelink02, which is also where
the GPU affinity wants it, and it means a dead node no longer strands plex.
Since the pod can therefore move, nothing that has to stay put may be derived
from the node it happens to be on.

`/transcode` is a **generic ephemeral volume** on `lvm-thin`, sized 96Gi. Plex
documents the requirement as "roughly equal to the size of the source file of
the transcode plus 100MB", and the library's largest file is a 50.3GiB 1080p
remux with a dozen more in the 27–37GiB band. An `emptyDir` big enough for that
would be sitting on the 100GiB node root filesystem, so this cannot be a
`sizeLimit` on `/`.

A generic ephemeral volume keeps the property that made `emptyDir` right —
created with the pod, deleted with it, so it is empty by construction rather
than by trusting Plex's own cleanup — while drawing from `thin-pool0`. Its size
is also the containment boundary: overrunning 96Gi gives Plex `ENOSPC` and fails
one playback, whereas exhausting the thin pool would return I/O errors to
*every* thin volume on that node, postgres and prometheus included.

Two things make this safe rather than merely bigger. The `lvm-thin` class mounts
with `discard` and the pool runs `discards=passdown`, so the constant
create-and-delete of HLS segments returns blocks to the pool immediately instead
of ratcheting allocation up to the provisioned size. And the pools are nearly
empty — 2.31% of 200GiB on beelink02, 0.73% of 300GiB on beelink01 — with
428GiB and 328GiB of unallocated VG behind them if the pool ever needs
extending.

Not tmpfs: a 50GiB transcode would take the pod's memory limit with it.
Not `piraeus-r2` either. Its `temporary-topolvm` pool is a thin LV on the *same*
`nvme0n1`, so the bytes land on the identical device; what the volume adds is
synchronous DRBD replication of scratch data over the network, plus a second
node-pinning constraint and one more thing to fail in the playback path. There
is nothing here for replication to protect.

### Database backups

Plex backs its databases up every three days (`ButlerTaskBackupDatabase`) and by
default drops the dated copies straight into `Plug-in Support/Databases`, the
same directory as the live SQLite files. The `backups` PVC (`unifi-nas`, same
pattern paperless and valheim use) is mounted at `/backup` to hold them
instead — but the manifest only provides the volume. **Pointing Plex at it is a
UI step**, under Settings → Scheduled Tasks with *Show Advanced* on:

> **Backup directory** → `/backup`

Until that is set the backups keep landing on the config volume; nothing breaks,
they are just in the less useful place. The setting is
`ButlerDatabaseBackupPath` in `Preferences.xml`, which lives on the config
volume and so survives restarts, but not a config wipe — worth re-checking after
any restore.

Only the **backups** belong on NFS. The live `com.plexapp.plugins.library.db`
and its `-wal`/`-shm` companions must stay on `piraeus-r2`: SQLite in WAL mode
needs file locking that NFS does not reliably provide, and the Plex image's own
README is blunt that a network share for the databases means "the vast majority
will result in database corruption". Mounting the whole `Databases` directory on
NFS is the obvious-looking move and it is the wrong one.

### Logs

Plex writes its real logs to files under `Plug-in Support/../Logs`, never to
stdout, so the node-level Alloy DaemonSet cannot see them. The `alloy` sidecar
tails them off the config volume (read-only, and the files are 0644 under
world-traversable directories, so it needs no matching uid) and ships them to
the same Loki as everything else, labelled `job="plex/logs"`.

It reads only the live files: the `.1.log`–`.5.log` rotations are excluded, or
each rotation would re-ingest a whole file, and `Plex Transcoder Statistics.log`
is excluded because it is XML rather than lines. Positions live on an emptyDir
with `tail_from_end`, which trades the lines written while the pod was down
against replaying the ~10MB server log on every restart.

### Metrics

None. The exporter this repo used to run needs a Plex token, which only exists
after the server is claimed, and a crash-looping sidecar would drop the pod out
of the Service — which, under `externalTrafficPolicy: Local`, withdraws the BGP
route as well.
