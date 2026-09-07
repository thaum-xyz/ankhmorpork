# Choose a storage class { .quad-howto }

Work through these in order and stop at the first one that matches. Each answer is
justified in [why storage is split the way it is](../explanation/storage-durability.md);
the full capability tables are in
[storage classes](../reference/storage-classes.md).

## 1. Does more than one Pod mount it at once?

If it genuinely needs **ReadWriteMany**, `unifi-nas` is the only option — piraeus
runs with `nfsServer.enabled: false` and provides no RWX.

Check that the RWX is real first. Charts often default to it defensively, and a
single-replica Deployment frequently needs it only because a RollingUpdate briefly
runs two Pods. Setting `strategy: Recreate` removes that need and puts the faster
classes back on the table.

## 2. Is it transactional?

Postgres, etcd, SQLite, or anything where an acknowledged write must survive a
power cut.

**Not `unifi-nas`.** It mounts `nfsvers=3` with `nolock`, so there is no
byte-range locking — SQLite in particular does not belong there at any speed.

That leaves the local classes — `lvm-thin` and the two piraeus classes, all of
which flush to the device. Continue to the next question.

## 3. Does the application replicate the data itself?

If yes — the CNPG clusters do, at the database layer — use **`lvm-thin`**. A
node-local volume per instance is correct there, and it is indistinguishable from
the bare device. It pins the Pod to one node, which is exactly what you want when
the redundancy lives a layer up.

Almost nothing else qualifies. If no, continue.

## 4. Is it bulk sequential?

Media libraries, backups, object storage — large, streamed, and not latency
sensitive. **`unifi-nas`**, at about 100 MiB/s on a single 1 GbE link, which is the
link and not the NAS.

Size alone does not send you here: a large volume that needs real latency belongs
on `piraeus-r2` in step 6.

## 5. Otherwise: `piraeus-r2-roaming`

**This is the default for ordinary application data**, and the most used class in
the cluster. Two synchronous replicas, and the Pod is free to schedule anywhere.

Performance is **the same as `piraeus-r2`**. The single difference: a Pod that
lands on a node holding no replica runs over the network until LINSTOR has
replicated the data there — degraded for a few minutes, identical afterwards.
That resync is also why PVCs here are **capped at 32 GiB** and denied above it.
The mechanism and the numbers are in the
[class comparison](../reference/storage-classes.md#piraeus-r2-and-piraeus-r2-roaming).

## 6. When to use `piraeus-r2` instead

Same two replicas and the same performance, but the Pod is pinned to a node
holding one of them (`allowRemoteVolumeAccess: false`), so it can never land
somewhere the data isn't.

Choose it over roaming when:

- the volume needs to exceed **32 GiB**, or
- the workload cannot tolerate a period of degraded I/O after a reschedule.

The trade is scheduling freedom: a Pod can only land on the two replica holders,
so if both are drained at once it waits.

## Then declare it

Nothing else is needed beyond the class name:

```yaml
spec:
  storageClassName: lvm-thin
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
```

`lvm-thin` and both piraeus classes use `WaitForFirstConsumer`, so the volume is
not provisioned until a Pod is scheduled. **Never pin that Pod with `nodeName`** —
it bypasses the scheduler, nothing writes
`volume.kubernetes.io/selected-node` on the PVC, the provisioner never fires, and
the PVC sits `Pending` forever. Use `nodeAffinity`.

## Changing your mind later

A PVC's class is immutable. Moving a workload between classes means provisioning a
new volume and copying the data — so the mobility question in step 4 is worth
answering honestly the first time.
