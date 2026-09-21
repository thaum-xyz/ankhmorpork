# esphome

A headless [ESPHome Device Builder](https://github.com/esphome/device-builder)
build server. It has no dashboard and holds no device configs: the ESPHome
add-on on Home Assistant keeps those, and sends every compile here over the
tailnet. Upstream calls this `--remote-build-only`.

| | |
| --- | --- |
| Reach it at | `builder.esphome.ankhmorpork.thaum.xyz`, port `6055` |
| Also | `192.168.50.136:6055`, the VIP behind that name |
| Protocol | Noise-encrypted WebSocket, `/remote-build/peer-link`; not HTTP, not TLS |
| Pairs with | exactly one sending dashboard |
| Image | the `image:` line in [`builder/deployment.yaml`](builder/deployment.yaml) |

## Pairing

The server accepts its first, and only, pairing during a fifteen-minute window
that opens on every start while nobody is paired. The window is gated on a
one-time key it prints to its log. If nothing pairs in time it exits, and the
restart opens a new window with a new key.

1. Read the banner. The seven emoji are the fingerprint; the last line is the
   key.

   ```bash
   kubectl -n esphome logs deployment/builder
   ```

2. On the sending dashboard, in the ESPHome add-on: **Settings → Send builds →
   Pair with a build server**. Enter the hostname and port from the table above
   and continue.

3. Compare the emoji the dialog shows against the banner. The dialog detects a
   headless server and asks for the key; enter it and send.

4. The server logs the approved peer and the dashboard lists it under **Paired
   build servers** as connected. Every Install from then on compiles here.

Missed the window, or need a fresh key:

```bash
kubectl -n esphome rollout restart deployment/builder
```

## Re-pairing

One pairing only: once a peer is approved the server never opens the window
again. To pair a different dashboard, or the same one after it lost its side of
the pairing, drop the approved peer and restart:

```bash
kubectl -n esphome exec deployment/builder -- rm /config/.receiver_peers.json
kubectl -n esphome rollout restart deployment/builder
```

`.device-builder-peer-link-key.bin` beside it is the identity. Deleting that
changes the fingerprint too, and the sending dashboard will refuse the
mismatch until it unpairs and pairs again.

## Caveats

### The tailnet is the transport, and upstream calls that best effort

Both beelinks advertise `192.168.50.0/24` to the tailnet, so a dashboard
anywhere on it reaches the VIP through whichever one holds the primary route.
The Service uses `externalTrafficPolicy: Cluster` for exactly that reason;
[plex's README](../plex/README.md) has the measurement. Two things on the
sending side have to hold:

- its Tailscale client accepts subnet routes, and
- it resolves `ankhmorpork.thaum.xyz` through the tailnet's split DNS, which
  points at the house resolver. Otherwise use the VIP.

Upstream designs the peer link for LAN latency and treats a VPN path as best
effort: it works, but a defect that only reproduces over a slow link will not
be pursued. Home Assistant sits a Tailscale hop away, so that is the deal here.

### Version match

The sending dashboard decides how far the two ESPHome versions may drift
(**Settings → Send builds**, version-match policy). At `release` the year and
month must match, so a Renovate bump here that the add-on has not had yet can
send builds back to local compilation, or refuse them at `exact_required`.

### Storage

Everything lives on `builder-data`: identity and pairing, then the PlatformIO
packages, the native ESP-IDF toolchains and one build directory per device.
Only the first few KiB are irreplaceable, and their loss costs a re-pair, so the
volume is not backed up. The first compile after a wipe re-downloads a
toolchain; expect it to take minutes rather than seconds.

### Nothing to scrape, nothing to probe

Headless mode binds no HTTP site, so there is no metrics endpoint and blackbox
has nothing it could probe. The probes are TCP checks on the peer-link port, and
`KubePodNotReady` is the alert that covers it.
