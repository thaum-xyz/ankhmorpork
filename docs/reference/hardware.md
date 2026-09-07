# Hardware { .quad-reference }

Mini-PCs in a cupboard, plus UniFi networking and a NAS.

Hardware surveyed 2026-09-07. Capacities are the physical devices, not current
usage. Node roles, scheduling state and labels are not here: they change without
any hardware changing, so read them from the cluster.

## Nodes

| Node | Chassis | CPU | RAM | Disks | Intel iGPU |
| --- | --- | --- | --- | --- | --- |
| `beelink01` | Beelink EQi12 | 16 | 32 GB | 1 TB NVMe | `0300-46a3` |
| `beelink02` | Beelink EQi12 | 16 | 32 GB | 1 TB NVMe | `0300-46a3` |
| `master01` | HP EliteDesk 800 G2 mini | 4 | 32 GB | 256 GB NVMe + 480 GB SSD | `0300-1912` |
| `master02` | HP EliteDesk 800 G2 mini | 4 | 16 GB | 256 GB NVMe + 500 GB SSD | `0300-1912` |

Workloads select a GPU by the `gpu.intel.com/device-id.<id>.present` label rather
than by node name, so the device ID is the part that matters.

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
