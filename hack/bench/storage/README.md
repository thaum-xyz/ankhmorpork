# StorageClass benchmark — ankhmorpork

Compares `longhorn`, `lvm-thin`, `piraeus-r2` and `unifi-nas`, one target at a
time, across `beelink01`, `beelink02` and `master02`.

**Looking for which class to use?** Read
[choose a storage class](https://docs.thaum.xyz/how-to/choose-a-storage-class/);
the measured ceilings are in [storage classes](https://docs.thaum.xyz/reference/storage-classes/)
and the reasoning in [why storage is split the way it is](https://docs.thaum.xyz/explanation/storage-durability/).
This README covers how the suite works.

Longhorn was retired on the strength of the 2026-09 run. Its targets stay in
`targets.env` commented out, so the comparison can be reproduced but a default
run does not try to provision a class that no longer exists. Raw results are
not committed; a run writes them to `results/`, which is ignored.

```bash
./full05.sh 4                              # both passes, 4 cycles each (~10h)

./run.sh --dry-run                         # see the plan, touch nothing
./run.sh --cycles 4 --buffered             # buffered pass, includes unifi-nas
./run.sh --cycles 4 --skip unifi-nas       # O_DIRECT pass, local classes only
./run.sh --resume dir05 --skip unifi-nas   # continue an interrupted run
./run.sh --only lvm-thin                   # filter by class or node substring
```

Two passes because the modes answer different questions. **Buffered** is how
applications actually behave and the only fair mode for `unifi-nas`; **O_DIRECT**
puts the page cache out of the way so the local classes are strictly comparable.
`unifi-nas` is skipped under O_DIRECT, where every write becomes its own
synchronous round trip that no application performs.

Cycles interleave across the whole matrix rather than running back to back, so
load on this live cluster spreads over every target instead of poisoning one.
Volumes are preconditioned once and reused across cycles — `--resume` keeps
completed cycles and reuses any volume whose layout actually finished, so an
interruption costs nothing already measured.

Results land in `results/<run-id>-<profile>/` with a `summary.md`, a
`results.csv`, the raw fio JSON per target, and the cluster state at run time.

## Why this shape

Every class is measured on **both** nodes, not just the one it is interesting
on. Measuring `lvm-thin` on two nodes but `piraeus-r2` on one makes "piraeus is
slower" unfalsifiable — it could just be a slower disk.

That matters because the two nodes are not alike:

| node | volume group | lvm-thin + piraeus pool | longhorn disk |
| --- | --- | --- | --- |
| `beelink01` | `ubuntu-vg` | `ubuntu-vg/thin-pool0` | `/dev/ubuntu-vg/longhorn` |
| `master02` | `secondary-vg` | `secondary-vg/thin-pool0` | `/dev/secondary-vg/longhorn` |

On each node all three local classes sit on the **same volume group**, so the
same physical device. A class-to-class difference *within* one node is therefore
stack overhead, not hardware. `piraeus-r2` is the sharpest case: its
`temporary-topolvm` storage pool *is* `thin-pool0`, the pool `lvm-thin` uses, so
`piraeus-r2` vs `lvm-thin` on one node isolates the cost of DRBD replication and
nothing else.

Runs are strictly serial for the same reason: two concurrent targets on a node
would be measuring each other.

## What it measures

Nine fio jobs per target: a layout pass that fully allocates the file first, QD1
latency with p99/p99.9, a `fsync=1` durable-commit test, QD64 IOPS ceilings, a
70/30 mix, and sequential throughput.

The `commit_fsync_4k_qd1` job is the one that decides whether a database can
live on a class at all — it is what all eleven CNPG clusters pay per commit.

Defaults: 8 GiB file in a 16 GiB volume, 45 s per job. The layout pass matters
more than it looks — on a thin pool, reads of unallocated blocks are served from
nowhere at fake speed, so nothing is measured until the file is fully written.

## O_DIRECT, and why NFS needs a second run

`direct=1` is the default: it is the only way to compare classes without the page
cache answering on their behalf.

It is also unrepresentative for `unifi-nas`. O_DIRECT on NFS turns every write
into its own synchronous round trip with no client-side coalescing, which no real
application does. A smoke run measured **26 write IOPS** at QD64 that way. Treat
that as a property of the test, not a verdict on the NAS, and pair it with:

```bash
./run.sh --only unifi-nas --buffered
```

Buffered runs go to a separate `-buffered` results directory so they can never be
accidentally compared against O_DIRECT ones.

Note also that `unifi-nas` mounts `nfsvers=3` with `nolock`, so there is no NFS
byte-range locking on that share regardless of performance.

## Not equivalent durability

The fast classes are partly fast because they promise less:

| class | replicas | failure domain |
| --- | --- | --- |
| `lvm-thin` | 1 | node loss = data loss |
| `piraeus-r2` | 2, DRBD sync | survives one node |
| `longhorn` | 3 | survives two nodes |
| `unifi-nas` | 1 share | survives any node, depends on the NAS |

Ranking them on IOPS alone compares different products.

## Operational notes

- Not Flux-managed, on purpose. The `bench` namespace exists only while a run is
  in flight and nothing here belongs in `k8s/apps` or `k8s/platform`.
- Pods pin with `nodeAffinity`, never `nodeName`. `nodeName` bypasses the
  scheduler, and `WaitForFirstConsumer` binding needs the scheduler to annotate
  the PVC with `volume.kubernetes.io/selected-node` — with `nodeName` the
  provisioner never fires and the PVC sits `Pending` forever. Both `lvm-thin` and
  `piraeus-r2` use delayed binding.
- Tolerations cover control-plane taints only, deliberately not
  `node.kubernetes.io/unschedulable`, so a heavy IO job cannot land on a node
  someone cordoned on purpose.
- Resource requests are set because the `require-resource-requests`
  ValidatingPolicy asks for them. The CPU limit is uniform and sized for
  `master02` (3700m allocatable), so fio is never the bottleneck on one node and
  throttled on another.
- Longhorn targets wait for `robustness: healthy` before fio starts; a rebuilding
  replica set would make the measurement worthless.
- Each target's PVC is deleted and its PV confirmed gone before the next starts,
  then a settle window passes, so no target competes with another's background
  delete.
- Thin pools do not return space to the VG until blocks are discarded. If `vgs`
  looks fuller than expected after a run, use `hack/lvm-trim.sh` from the
  ankhmorpork repo on the tested nodes.
- This will move disk latency and Longhorn metrics enough to trip alerts. Silence
  them first if you would rather not page yourself:
  ```bash
  amtool --alertmanager.url=<url> silence add \
    --duration=2h --comment="storage benchmark" 'node=~"beelink01|master02"'
  ```

## Layout

```
run.sh                  orchestrator, serial, one target at a time
report.py               fio JSON -> summary.md + results.csv
targets.env             the matrix; beelink02 and master01 commented out
                        (master01 is cordoned)
fio/modern.fio          the job definitions
manifests/              namespace, PVC/Job templates, pod entrypoint
results/                run output
```

`fio` is installed at pod start from Alpine `3.24.1`, so the pods need egress.
The entrypoint fails loudly if that install does not work.
