# Why storage is split the way it is { .quad-explanation }

Three storage stacks for one small cluster looks like indecision. They exist
because the workloads want genuinely different things — and the shape of the split
was settled by a measurement, not a preference.

The practical outcome is in
[choose a storage class](../how-to/choose-a-storage-class.md); the tables are in
[storage classes](../reference/storage-classes.md). This page is the reasoning.

## Speed and durability are not the same axis

Ranking storage on IOPS compares different products. The fast ones are partly fast
because they promise less:

| Class | Replicas | Failure domain |
| --- | --- | --- |
| `lvm-thin` | 1 | node loss = data loss |
| `piraeus-r2` | 2, DRBD synchronous | survives one node |
| `unifi-nas` | 1 share | depends on the NAS |

A benchmark that only measures throughput therefore cannot tell you which class to
use. The question that matters for a database is narrower: **when the storage says
a commit is durable, is it?**

## How you test that at all

You cannot ask a storage layer whether it is honest. But you can measure it
against the device beneath it, because of one constraint:

> Nothing can be faster than the device it writes to.

A class whose `fsync` completes *faster* than the bare disk underneath is not
waiting for that disk. That turns a question about trust into a measurement — and
it is why the benchmark keeps a `hostpath-*` target on every node, writing straight
to the same LV with no CSI driver in the path. Without that control, a class that
skips the flush simply looks fast.

Every local class on a node uses the same volume group, so a difference measured
*within* a node is stack overhead rather than hardware.

`lvm-thin` tracks its device at parity. `piraeus-r2` pays more than its device,
which is what synchronous replication should look like. Both are honest.

## The class that was not

Longhorn was the fourth stack here, and this test is why it is gone.

Its `fsync` completed **2–8× faster than the disk it sat on**, and barely moved —
752, 891, 630 µs across three nodes — while the devices beneath differed by 2.7×. A
number that ignores the hardware underneath is not measuring the hardware.

The mechanism was in the source rather than inferred from timings. Replica files
are opened `O_DIRECT` (`sparse.NewDirectFileIoProcessor`), so writes bypass the
host page cache — but the controller-to-replica protocol defines only `TypeRead`,
`TypeWrite`, `TypeUnmap` and control messages. **There is no flush operation**, so
a flush could not reach the replica's storage at all. `Sync()` was called only on
snapshot and expand.

Because `O_DIRECT` did put data on the drive, a pod kill, node reboot or kernel
panic was survivable. The exposure was **sudden power loss**, where the drive's
volatile cache is lost.

A second line of evidence agreed. Running the whole matrix twice, buffered and
`O_DIRECT`, separates classes limited by storage from classes limited by their own
software — 4 KiB random write IOPS on beelink01:

| Class | O_DIRECT | Buffered | Gain |
| --- | --- | --- | --- |
| bare device | 132.0k | 190.8k | 1.45× |
| `lvm-thin` | 86.5k | 163.9k | 1.89× |
| `piraeus-r2` | 11.9k | 26.4k | 2.22× |
| Longhorn | 13.2k | 13.1k | **0.99×** |

It was the only class the page cache could not help. A class that caching cannot
accelerate is not limited by its storage; it is limited by its own engine. Its flat
55 MiB/s sequential write ceiling, unchanged across three disks differing by 3×,
said the same thing from the other direction.

Its headline commit rate — 678/s, the highest measured anywhere in the fleet — was
the least trustworthy number in the table. Nothing transactional was ever moved
onto it, and it was retired rather than kept for the snapshots and S3 backup it
offered; that capability is being replaced instead of traded against durability
([#1266](https://github.com/thaum-xyz/ankhmorpork/issues/1266)).

## What the split is for

- **`lvm-thin`** for anything that replicates itself. The CNPG clusters do, at the
  database layer, so a node-local volume per instance is correct and costs
  essentially nothing over the bare device. It pins the Pod to one node, which is
  the price.
- **`piraeus-r2-roaming`** for ordinary application data, and in practice the
  most used class here. Two synchronous replicas, and the Pod is free to schedule
  anywhere: it attaches diskless on a node without a replica and `auto-diskful`
  converts that into a local one after five minutes. The steady state is therefore
  a local disk; what you pay for the freedom is a window after each move, and the
  32 GiB cap that keeps that window bounded.
- **`piraeus-r2`** for the same data when it must exceed 32 GiB, or when five
  minutes of remote I/O after a reschedule is unacceptable. The Pod is pinned to a
  replica holder, so I/O is always local. Reads are free, at parity with raw LVM on
  the same thin pool; writes pay the full cost of synchronous replication, capped
  at 111 MiB/s by the replication link on every node.
- **`unifi-nas`** for bulk sequential and for the only RWX in the cluster, at the
  ~100 MiB/s a single 1 GbE link allows. `nconnect=4` does not lift it: the switch
  hashes on MAC and IP, and a routed client-to-NAS flow presents one of each, so
  extra connections land on the same bond member.

## How much to trust this

100 measurements, four interleaved cycles per target per mode, one target at a
time so that two never measure each other.

The honest caveats: `fsync` on the bare-device baselines is the noisiest figure
here at CV 24–61%, so ratios near 1× prove nothing — the 2–8× margin above is far
outside that, but `lvm-thin` on beelink01 reading 1.4× is inconclusive, not a
finding. The hostPath baseline was an exact reference for Longhorn, which wrote to
that same LV, but is only approximate for `lvm-thin` and `piraeus-r2`, which use a
thin pool in the same volume group. And `piraeus-r2`'s sequential read exceeding
the bare device remains unexplained.

Method and raw results: `bench/storage-2026-09/` (local, untracked), re-runnable
with `./full05.sh 4`.
