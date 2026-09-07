# Storage classes { .quad-reference }

Capabilities and measured ceilings. To pick one, use
[choose a storage class](../how-to/choose-a-storage-class.md); for why they differ,
see [why storage is split the way it is](../explanation/storage-durability.md).

Numbers are medians of four interleaved cycles, measured 2026-09-05 on
`beelink01`, `beelink02` and `master02`.

## Mobility and access modes

Often the binding constraint, and independent of speed.

| Class | Provisioner | Binding | Nodes a Pod can land on | Access modes | Survives a kured drain |
| --- | --- | --- | --- | --- | --- |
| `lvm-thin` | `topolvm.io` | WaitForFirstConsumer | **1** | RWO | **no** |
| `piraeus-r2` | `linstor.csi.linbit.com` | WaitForFirstConsumer | **2** (replica holders) | RWO | yes |
| `piraeus-r2-roaming` | `linstor.csi.linbit.com` | WaitForFirstConsumer | any linstor node | RWO | yes |
| `unifi-nas` | `nfs.csi.k8s.io` | Immediate | any | RWO, RWX | yes |

## Durability

Every class here flushes an acknowledged write to the device.

| Class | Replicas | Failure domain |
| --- | --- | --- |
| `lvm-thin` | 1 | node loss = data loss |
| `piraeus-r2` | 2, DRBD synchronous | survives one node |
| `piraeus-r2-roaming` | 2, DRBD synchronous | survives one node |
| `unifi-nas` | 1 share | survives any node, depends on the NAS |

## Constraints

| Class | Constraint |
| --- | --- |
| `piraeus-r2-roaming` | PVCs capped at **32 GiB**; larger are denied at admission |
| `unifi-nas` | `nfsvers=3` with `nolock` — no byte-range locking, so nothing SQLite-backed |
| `unifi-nas` | PVCs are labelled `excluded_from_alerts=true` automatically; expected, not drift |
| `lvm-thin`, `piraeus-r2*` | `WaitForFirstConsumer` — a Pod pinned with `nodeName` leaves the PVC `Pending` forever |
| all | `parameters`, `mountOptions`, `provisioner`, `reclaimPolicy` and `volumeBindingMode` are immutable |

## Measured ceilings

### O_DIRECT — what the storage stack costs

Bare-device rows are a hostPath onto the same disk with no CSI driver in the path.
`piraeus-r2` rows apply to `piraeus-r2-roaming` equally.

| Target | QD1 write | rd IOPS | wr IOPS | seq rd MiB/s | seq wr MiB/s |
| --- | --- | --- | --- | --- | --- |
| bare device · beelink01 | 7.8 µs | 184.2k | 132.0k | 625 | 1 119 |
| `lvm-thin` · beelink01 | 11.9 µs | 156.3k | 86.5k | 711 | 1 080 |
| `piraeus-r2` · beelink01 | 3 068 µs | 179.9k | 11.9k | 2 646 | **111** |
| bare device · master02 | 32.8 µs | 92.5k | 81.0k | 418 | 357 |
| `lvm-thin` · master02 | 35.3 µs | 93.3k | 80.8k | 418 | 353 |
| `piraeus-r2` · master02 | 987 µs | 93.7k | 22.7k | 496 | **111** |

`piraeus-r2` sequential write is 111 MiB/s on **every** node, so it is the
replication link rather than the disk.

### Buffered — how applications actually behave

The only fair mode for `unifi-nas`.

| Target | rd IOPS | wr IOPS | seq rd MiB/s | seq wr MiB/s | commits/s |
| --- | --- | --- | --- | --- | --- |
| bare device · beelink01 | 53.8k | 190.8k | 440 | 848 | 500 |
| `lvm-thin` · beelink01 | 50.7k | 163.9k | 536 | 916 | 285 |
| `piraeus-r2` · beelink01 | 53.6k | 26.4k | 954 | **111** | 132 |
| `unifi-nas` · beelink01 | 300 | 815 | 99 | 82 | 12 |

### `piraeus-r2` and `piraeus-r2-roaming`

Both place two synchronous replicas from the same `temporary-topolvm` pool, use
xfs, and carry the same DRBD tuning. They differ only in where the Pod may run:

| | `piraeus-r2` | `piraeus-r2-roaming` |
| --- | --- | --- |
| `allowRemoteVolumeAccess` | `false` | `true` |
| Pod may schedule on | the 2 replica holders | any linstor node |
| Performance, steady state | identical | identical |
| Landing on a node with no replica | cannot happen | **degraded** until LINSTOR replicates to it |
| `auto-diskful` delay | — | **5 minutes**, then a local replica, surplus dropped |
| Max PVC size | unbounded | **32 GiB**, denied above |

How the "Pod may schedule on" row is enforced differs, and the difference bites.
`piraeus-r2` PVs carry node affinity for their two replica holders, written by
the driver, so the scheduler honours that row on its own. `piraeus-r2-roaming`
PVs carry no node affinity at all — being attachable from anywhere is the point —
so once the claim is bound, nothing keeps a Pod off a node with no CSI node
plugin, where it waits forever on `CSINode <node> does not contain driver
linstor.csi.linbit.com`. A Pod mounting a roaming volume needs its own
[`linbit.com/hostname`](annotations.md) affinity.

Both classes restrict *provisioning* through `allowedTopologies` on
`linbit.com/hostname`, patched in through the HelmRelease's `postRenderers`
because the chart's template does not render that field. Under
`WaitForFirstConsumer` the scheduler applies it while the claim is unbound, so a
new volume is steered to a node that can serve it — it does nothing for a claim
that is already bound.

The size cap is a resync budget: a moved Pod resyncs the volume across the node
network, and a full 32 GiB is roughly five more minutes at 1 Gb/s.
`rs-discard-granularity` keeps unallocated blocks off the wire, but requested size
is the only proxy admission has.

#### DRBD tuning

Both classes carry `al-extents=6433` (the maximum, covering ~25 GiB) and
`max-buffers=8000`, merged 2026-09-03. DRBD writes activity-log metadata
synchronously whenever a write lands in an extent it is not already tracking, and
the default 1237 extents cover only ~4.8 GiB, so random writes over a larger
volume thrash the log.

Measured on beelink01/beelink02/master02 with an 8 GiB working set:

| Metric | Before | After |
| --- | --- | --- |
| Random write IOPS | 3 833 / 3 751 / 7 491 | 11 800 / 11 500 / 24 100 (**3.1–3.2×**) |
| QD1 write latency | — | **−35% / −34% / −46%** |
| Durable commits | — | **+19–28%** |

Reads are unchanged, as expected — the activity log only gates writes. Neither
option trades away durability.

## Caveats on these numbers

- `piraeus-r2` sequential read of 2 646–3 252 MiB/s exceeds the bare device's
  625–674 MiB/s and is **unexplained**. Treat it as anomalous, not as a result.
- `unifi-nas` was measured on one node, buffered only.
- fsync on the bare-device baselines is the noisiest measurement, CV 24–61%.

Method: [`hack/bench/storage/`](https://github.com/thaum-xyz/ankhmorpork/tree/master/hack/bench/storage).
Raw results are not in the repository. The numbers describe the nodes named above
on the date given — re-measure after a node, disk, network or DRBD option change.
