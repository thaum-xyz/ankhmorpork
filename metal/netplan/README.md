# Host networking

Not Ansible-managed yet. `bond0` on each node comes from cloud-init
(`/etc/netplan/50-cloud-init.yaml`); the files here are applied by hand.

## beelink02 VLAN20 (DLNA)

minidlna announces over SSDP (`239.255.255.250:1900`), which is scoped to a
broadcast domain. The UDM routes unicast between VLAN50 and VLAN20 but does not
forward that multicast, and its "Multicast DNS" toggle only relays mDNS
(`224.0.0.251`) — a different group. So the TV in VLAN20 can only discover the
server if the host has an interface in VLAN20 itself.

Pinned to beelink02 because it is the only non-control-plane node. Putting an
IoT VLAN on a control-plane node would place the API and etcd on the same
segment as a TV.

### Prerequisite: tag VLAN20 on the switch

`bond0` is an 802.3ad LACP bond of `enp170s0` + `enp171s0`, so **both** member
ports need VLAN20 tagged in their UniFi port profile (native stays VLAN50).
Without it the interface comes up and stays silent.

Verify before applying — a live VLAN shows RX traffic within seconds:

```bash
sudo ip link add link bond0 name bond0.20 type vlan id 20
sudo ip link set bond0.20 up
sleep 30 && ip -s link show bond0.20   # RX 0 packets => not tagged yet
sudo ip link del bond0.20
```

### Apply

The file is already installed at `/etc/netplan/60-vlan20.yaml` and passes
`netplan generate`. It is deliberately **not applied**: until VLAN20 is tagged,
activating it routes `192.168.20.0/24` down a dead interface.

**Do not apply over an SSH session sourced from VLAN20.** Workstations live in
that VLAN, so applying blackholes the return path and drops the session
mid-command — recovery is via the rack console. Connect over Tailscale
(`100.114.34.93`) or from VLAN50 instead, and check first:

```bash
ss -tunap | grep ':22 '     # is your own session sourced from 192.168.20.x?
```

Confirm `192.168.20.37` sits outside VLAN20's DHCP pool, then:

```bash
sudo netplan generate && sudo netplan apply
```

Then set `MINIDLNA_NETWORK_INTERFACE=bond0,bond0.20` on the deployment so it
announces into both domains, and keep the node labelled `dlna-preferred=true`.

Note `net.ipv4.ip_forward=1` on every k8s node, so a multi-homed node is a
latent router between the two segments — it sits beside the UDM, not behind it.

## Deferred: filter the VLAN20 interface

Not implemented — noted for later. Today the host's wildcard-bound ports (SSH,
rpcbind, and anything else on `0.0.0.0`) would answer on the IoT VLAN, and
Cilium's `devices=` is empty (auto-detect), so `bond0.20` gets adopted into the
NodePort datapath. There are 0 NodePort services now, but that is latent.

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
