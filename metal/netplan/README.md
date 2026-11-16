# Host networking

Not Ansible-managed yet. `bond0` on each node comes from cloud-init
(`/etc/netplan/50-cloud-init.yaml`); the files here are applied by hand.

## beelink02 VLAN20 (DLNA)

**Applied 2026-08-23.** `/etc/netplan/60-vlan20.yaml` on beelink02.

minidlna announces over SSDP (`239.255.255.250:1900`), which is scoped to a
broadcast domain. The UDM routes unicast between VLAN50 and VLAN20 but does not
forward that multicast, and its "Multicast DNS" toggle only relays mDNS
(`224.0.0.251`) — a different group. So the host needs a leg in VLAN20 itself.

Pinned to beelink02 because it is the only non-control-plane node. Putting an
IoT VLAN on a control-plane node would place the API and etcd on the same
segment as a TV. That objection disappears once the Talos migration moves the
control plane onto dedicated hardware.

`192.168.20.37` is below VLAN20's DHCP pool, which starts at `.50`.

### No switch change is needed

The UniFi port profile already has **Tagged VLAN Management: "Allow All"** with
native VLAN50, which delivers every other VLAN tagged. There is no per-VLAN
checkbox to find, and nothing to change for a new VLAN on these ports.

### Probing: test actively, not passively

Do **not** conclude anything from a silent interface. Watching RX counters on a
fresh sub-interface showed 0 packets over 72s here and looked exactly like a
missing tag — VLAN20 was simply idle, because the TV was its only occupant.

Force ARP instead. A resolved neighbour proves tagged frames flow both ways:

```bash
sudo ip link add link bond0 name vl20probe type vlan id 20
sudo ip link set vl20probe up
sudo ip addr add 192.168.20.37/24 dev vl20probe noprefixroute   # no route added
sudo ip route add 192.168.20.1/32 dev vl20probe src 192.168.20.37
timeout 4 bash -c 'echo > /dev/tcp/192.168.20.1/443'
ip neigh show dev vl20probe        # a lladdr => works; INCOMPLETE => does not
sudo ip route del 192.168.20.1/32 dev vl20probe; sudo ip link del vl20probe
```

`noprefixroute` plus a host route keeps the probe from stealing the
`192.168.20.0/24` path while a workstation in that VLAN holds an SSH session.

### Applying without locking yourself out

Workstations live in VLAN20, so activating the drop-in moves the return path for
your own session. Run it detached so a dropped session cannot leave it
half-applied:

```bash
sudo systemd-run --on-active=3 --unit=netplan-vlan20-apply /usr/sbin/netplan apply
```

Afterwards the node also answers on `192.168.20.37`, a symmetric path inside
VLAN20. Expect one stale-ARP failure before the first connection succeeds.

Note `net.ipv4.ip_forward=1` on every k8s node, so a multi-homed node is a
latent router between the two segments — it sits beside the UDM, not behind it.

### VLAN50-sourced replies go back through the UDM

The connected `192.168.20.0/24` route sends every reply to a VLAN20 client out
`bond0.20`, including replies from LB VIPs. The UDM then sees one direction
only and drops the rest of the flow. Measured 2026-11-15 from `192.168.20.4` to
`192.168.50.137:5432`: SYN-ACKs arrived from beelink02's VLAN20 MAC and were
retransmitted until the client timed out. Applied 2026-11-16: 10 of 10 Postgres
handshakes from that host completed.

The rule at priority 5240 sends anything sourced from `192.168.50.0/24` to
table 20, whose only route is VLAN20 via the UDM. Traffic sourced from
`192.168.20.37` (minidlna) and pod-sourced traffic keep the direct leg.

```bash
sudo install -m 0600 beelink02-60-vlan20.yaml /etc/netplan/60-vlan20.yaml
sudo netplan generate
sudo systemd-run --on-active=3 --unit=netplan-vlan20-apply /usr/sbin/netplan apply
```

```bash
ip rule show | grep 5240                              # from 192.168.50.0/24 to 192.168.20.0/24 lookup 20
ip route get 192.168.20.4 from 192.168.50.137 iif lo  # via 192.168.50.1 dev bond0
ip route get 192.168.20.4                             # dev bond0.20 src 192.168.20.37
```

The real check is from a VLAN20 host: a connection to a VIP whose backend runs
on beelink02 must get its SYN-ACK from the UDM's MAC and complete.

## beelinks: local subnets ahead of Tailscale's table 52

Two `routing-policy` rules on `bond0`, on beelink01 and beelink02. On both
nodes they sit inline in `/etc/netplan/50-cloud-init.yaml` (edited 2026-09-27,
read back 2026-11-16); there is no separate drop-in.
`beelinks-61-tailscale-local-subnets.yaml` holds the same rules as a drop-in for
a rebuilt node. They must be in place **before** `--accept-routes` is turned on.
Both are set by hand; `30_tailscale.yml` does not touch either, and Ansible is
on its way out.

`--accept-routes` is there so that replies to another site's LAN go back over
the tunnel. Banacha's `192.168.110.0/24` reaches the UNAS through HA's subnet
router; this is a stopgap until UniFi site-to-site replaces it.

Both beelinks advertise `192.168.40.0/24` and `192.168.50.0/24`; only one holds
the primary route. With `--accept-routes`, the other one installs its partner's
copy into table 52, and `5270: from all lookup 52` sits ahead of
`32766: from all lookup main`. Tested on beelink02 (standby) on 2026-09-27:
table 52 held both subnets within 5 s, so the node sent its own LAN and the NAS
(`192.168.40.10`) through the tunnel until rolled back with
`tailscale set --accept-routes=false`. The primary can move, so both nodes need
the fix.

The two rules at priority 5260 send these subnets to the main table first.
Routes from other sites (e.g. Banacha's `192.168.110.0/24`) still come from
table 52. They are netplan `routing-policy` rather than `ip rule add`, because
systemd-networkd deletes rules it does not own when it reconfigures a link.

The subnets must match `tailscale_advertise_routes` in
`group_vars/tailscale_subnet_router.yml`.

### Applying

On a node whose `50-cloud-init.yaml` lacks the rules:

```bash
sudo install -m 0600 beelinks-61-tailscale-local-subnets.yaml /etc/netplan/61-tailscale-local-subnets.yaml
sudo netplan get bonds.bond0          # routing-policy merged into the cloud-init bond
sudo netplan generate                 # fails on a bad merge before anything changes
sudo systemd-run --on-active=3 --unit=netplan-tailscale-rules-apply /usr/sbin/netplan apply
```

`netplan apply` can reconfigure `bond0` for a moment. On beelink01 that is a
control-plane node, so apply there when a short API/etcd blip is acceptable.

Only once `ip rule show | grep 5260` lists both rules:

```bash
sudo tailscale set --accept-routes
```

beelink02 (worker) first, then beelink01. Undo with
`sudo tailscale set --accept-routes=false`.

### Checking

```bash
ip rule show | grep 5260                 # two "to 192.168.x.0/24 lookup main" rules
ip route get 192.168.40.10               # dev bond0, not tailscale0
ip route get 192.168.110.10              # dev tailscale0, once --accept-routes is on
tailscale debug prefs | jq .RouteAll     # true
```

### Removing

When UniFi site-to-site takes over: `sudo tailscale set --accept-routes=false`
on both, then remove the two priority-5260 rules from
`/etc/netplan/50-cloud-init.yaml` (or delete the `61-` drop-in where one was
installed) and `netplan apply`, in that order.

### tailscaled ports: 41641 on beelink01, 41642 on beelink02

Both nodes sit behind the same two NATs, and neither can take an inbound port
forward (see `k8s/apps/plex/README.md`). On the shared default port only one of
them keeps a predictable external port. The other fell back to DERP: beelink02
reached Banacha's HA via `DERP(waw)` while beelink01 went direct.

beelink02 runs on its own port, set by hand on 2026-09-27:

```bash
echo 'PORT="41642"' | sudo tee -a /etc/default/tailscaled   # edit an existing PORT= line instead
sudo systemctl restart tailscaled
tailscale ping -c 5 <peer>        # "via <ip>:<port>", not "via DERP(...)"
```

Afterwards beelink02 → HA went direct in 29 ms. This only matters when
beelink02 holds the primary route, e.g. while beelink01 reboots under kured.
Otherwise Banacha's backups and scans would take the relay.

## Deferred: filter the VLAN20 interface

Not implemented — noted for later. Today the host's wildcard-bound ports (SSH,
rpcbind, and anything else on `0.0.0.0`) answer on the IoT VLAN, and Cilium's
`devices=` is empty (auto-detect), so `bond0.20` gets adopted into the NodePort
datapath. There are 0 NodePort services now, but that is latent.

Intent is to allow only SSDP and minidlna's HTTP port inbound, and to refuse
transit into VLAN50:

```
iif bond0.20 udp dport 1900 accept
iif bond0.20 tcp dport 8200 accept
iif bond0.20 ct state established,related accept
iif bond0.20 drop
iif bond0.20 oif bond0 drop        # no VLAN20 -> VLAN50 transit
```

Raw nftables is the wrong tool here: k3s and Cilium own the host chains, and in
BPF mode traffic can bypass them. Use Cilium's host firewall
(`CiliumClusterwideNetworkPolicy` with a `nodeSelector`) instead, or pin
Cilium's `devices` so it never claims `bond0.20`.
