# Why storage is split four ways { .quad-explanation }

Four storage classes look like indecision. They exist because the workloads here
want genuinely different things, and because one of the four turned out not to
provide what its numbers suggested.

The practical outcome is in
[choose a storage class](../how-to/choose-a-storage-class.md); the tables are in
[storage classes](../reference/storage-classes.md). This page is the reasoning.

## Speed and durability are not the same axis

Ranking storage classes on IOPS compares different products. The fast ones are
partly fast because they promise less:

| Class | Replicas | Failure domain |
| --- | --- | --- |
| `lvm-thin` | 1 | node loss = data loss |
| `piraeus-r2` | 2, DRBD synchronous | survives one node |
| `longhorn` | 3 | survives two nodes |
| `unifi-nas` | 1 share | depends on the NAS |

So a benchmark that only measures throughput cannot tell you which class to use.
The question that matters for a database is narrower: **when the storage says a
commit is durable, is it?**

## How you test that at all

You cannot ask a storage layer whether it is honest. But you can measure it
against the device beneath it, because of one constraint:

> Nothing can be faster than the device it writes to.

A class whose `fsync` completes *faster* than the bare disk underneath is not
waiting for the disk. That turns a question about trust into a measurement — and
it is why the benchmark keeps a `hostpath-*` target on every node, writing
straight to the same LV with no CSI driver in the path. Without that control, a
class that skips the flush simply looks fast.

The same volume group is used for every local class on a node, so a difference
within a node is stack overhead rather than hardware.

## What that found

`fsync` latency, each class against the device it writes to:

| Node | Bare device | Longhorn, 3 replicas |
| --- | --- | --- |
| beelink01 | 2 858 µs | **752 µs** |
| beelink02 | 1 958 µs | **891 µs** |
| master02 | 5 279 µs | **630 µs** |

Longhorn completes a flush **2–8× faster than the disk it sits on**, and barely
moves — 752, 891, 630 µs — while the devices beneath differ by 2.7×. A number that
ignores the hardware underneath is not measuring the hardware.

`lvm-thin` and `piraeus-r2` both track their device: `lvm-thin` at parity,
`piraeus-r2` paying more, which is what synchronous replication should look like.

### The mechanism

The reason is in Longhorn's source rather than inferred from timings. Replica
files are opened `O_DIRECT` (`sparse.NewDirectFileIoProcessor`), so writes bypass
the host page cache — but the controller-to-replica protocol defines only
`TypeRead`, `TypeWrite`, `TypeUnmap` and control messages. **There is no flush
operation**, so a flush cannot reach the replica's storage at all. `Sync()` is
called only on snapshot and expand.

Because `O_DIRECT` does put the data on the drive, a pod kill, node reboot or
kernel panic is survivable. The exposure is **sudden power loss**, where the
drive's volatile cache is lost. Drives with power-loss protection would close the
gap; a 2–5 ms flush cost on the bare device indicates these do not have it.

### A second line of evidence

Running the whole matrix twice, buffered and `O_DIRECT`, separates classes limited
by storage from classes limited by their own software. 4 KiB random write IOPS on
beelink01:

| Class | O_DIRECT | Buffered | Gain |
| --- | --- | --- | --- |
| bare device | 132.0k | 190.8k | 1.45× |
| `lvm-thin` | 86.5k | 163.9k | 1.89× |
| `piraeus-r2` | 11.9k | 26.4k | 2.22× |
| `longhorn` | 13.2k | 13.1k | **0.99×** |

Longhorn is the only class the page cache cannot help. A class that caching cannot
accelerate is not limited by its storage — it is limited by its own engine. Its
flat 55 MiB/s sequential write ceiling, unchanged across three disks differing by
3×, says the same thing from the other direction.

## What followed

Longhorn's headline commit rate — 678/s, the highest measured anywhere in the
fleet — was the least trustworthy number in the table. Nothing transactional was
ever moved onto it, and its retirement is tracked in
[#1266](https://github.com/thaum-xyz/ankhmorpork/issues/1266). What it offered that
the others do not — snapshots, S3 backup, a UI — is being replaced rather than
traded against durability.

The remaining split then has a straightforward shape:

- **`lvm-thin`** for anything that replicates itself. The CNPG clusters do, at the
  database layer, so a node-local volume per instance is correct and costs
  essentially nothing over the bare device.
- **`piraeus-r2`** where the data itself must survive a node. Reads are free, at
  parity with raw LVM on the same thin pool; writes pay the full cost of
  synchronous replication, capped at 111 MiB/s by the replication link on every
  node.
- **`unifi-nas`** for bulk sequential and for the only RWX in the cluster, at the
  ~100 MiB/s a single 1 GbE link allows. `nconnect=4` does not lift it: the switch
  hashes on MAC and IP, and a routed client-to-NAS flow presents one of each, so
  extra connections land on the same bond member.

## How much to trust this

100 measurements, four interleaved cycles per target per mode, one target at a
time so that two never measure each other.

The honest caveats: `fsync` on the bare-device baselines is the noisiest figure
here at CV 24–61%, so ratios near 1× prove nothing — Longhorn's 2–8× margin is far
outside that, but `lvm-thin` on beelink01 reading 1.4× is inconclusive, not a
finding. The hostPath baseline is an exact reference for Longhorn, which writes to
that same LV, but only approximate for `lvm-thin` and `piraeus-r2`, which use a
thin pool in the same volume group. And `piraeus-r2`'s sequential read exceeding
the bare device remains unexplained.

Method and raw results: `bench/storage-2026-09/` (local, untracked), re-runnable
with `./full05.sh 4`.
