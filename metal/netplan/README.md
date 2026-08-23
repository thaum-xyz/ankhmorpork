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
