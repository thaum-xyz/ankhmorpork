# Hardware { .quad-reference }

Mini-PCs in a cupboard, plus UniFi networking and a NAS. Node roles and
scheduling labels are what most decisions here actually turn on; see
[nodes and labels](#nodes-and-labels).

Hardware surveyed 2026-09-07. Capacities are the physical devices, not current
usage.

## Nodes

| Node | Chassis | CPU | RAM | Disks |
| --- | --- | --- | --- | --- |
| `beelink01` | Beelink EQi12 | 16 | 32 GB | 1 TB NVMe |
| `beelink02` | Beelink EQi12 | 16 | 32 GB | 1 TB NVMe |
| `master01` | HP EliteDesk 800 G2 mini | 4 | 32 GB | 256 GB NVMe + 480 GB SSD |
| `master02` | HP EliteDesk 800 G2 mini | 4 | 16 GB | 256 GB NVMe + 500 GB SSD |

The two chassis generations differ enough to matter: the beelinks carry
substantially more cores, and a single fast device where the EliteDesks pair a
small NVMe for the OS with a SATA SSD for data.

## Storage layout

Each node presents one LVM volume group to topolvm, and which device backs it
differs by chassis.

| Node | topolvm VG | Backed by | OS root |
| --- | --- | --- | --- |
| `beelink01`, `beelink02` | `ubuntu-vg` | the 1 TB NVMe, shared with the OS | same device |
| `master01`, `master02` | `secondary-vg` | the SATA SSD | the 256 GB NVMe |

`lvm-thin` and `piraeus-r2` both allocate from `thin-pool0` in that group, so on
any node they sit on the same physical device — which is what makes a
class-to-class comparison on one node measure stack overhead rather than
hardware. See [storage durability](../explanation/storage-durability.md).

The EliteDesks keep the OS off the data device; the beelinks do not.

## Nodes and labels

Labels, not hardware, decide where most workloads land.

| Node | Control plane | Schedulable | linstor | Notable labels |
| --- | --- | --- | --- | --- |
| `beelink01` | yes, etcd | yes | yes | — |
| `beelink02` | no | yes | yes | `dlna-preferred`, `network.infra/type: fast` |
| `master01` | yes, etcd | **no** | no | `network.infra/ingress`, `network.infra/loadbalancer` |
| `master02` | yes, etcd | **no** | yes | `network.infra/ingress`, `network.infra/loadbalancer` |

Both EliteDesks are cordoned, so ordinary workloads land only on the two
beelinks. That is the binding constraint on any `topologySpreadConstraint` or
anti-affinity rule: a Deployment asking for spread across three nodes will not get
it.

`master01` carries no `linstor` label, so it holds no DRBD replicas even though it
has a `secondary-vg`. Piraeus therefore places its two replicas on the beelinks
and `master02`.

`beelink02` is the only node outside the control plane, which is why the VLAN20
leg for DLNA lives there — see `metal/netplan/README.md`.

Every node carries `network.infra/bgp: "65020"` and an Intel integrated GPU
exposed through the device plugin: `0300-46a3` on the beelinks, `0300-1912` on the
EliteDesks. Workloads select a GPU by the
`gpu.intel.com/device-id.<id>.present` label rather than by node name.

## Network and storage appliances

| Device | Role |
| --- | --- |
| UniFi Dream Machine Pro | router, and the DNS resolver external-dns writes into |
| UniFi USW-24-Pro Max | switch |
| UniFi UNAS Pro | NAS backing the `unifi-nas` storage class |

The UNAS Pro is reached over a single 1 GbE path from the cluster, which is the
ceiling on `unifi-nas` throughput — not the NAS itself. See
[storage classes](storage-classes.md).

DNS is served by the UDM Pro; external-dns publishes records into it through the
UniFi integration API, so a name only resolves on the LAN once that record exists.
See [ingress and certificates](ingress.md).
