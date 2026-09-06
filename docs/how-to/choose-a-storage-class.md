# Choose a storage class { .quad-howto }

Work through these in order and stop at the first one that matches. Each answer
is justified in [why storage is split this way](../explanation/storage-durability.md);
the full capability tables are in
[storage classes](../reference/storage-classes.md).

!!! warning "Longhorn is being retired"

    Do not choose `longhorn`, `longhorn-r2` or `longhorn-static` for anything new.
    An acknowledged write on Longhorn is not flushed to the device, and its
    retirement is tracked in
    [#1266](https://github.com/thaum-xyz/ankhmorpork/issues/1266).

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

- **Not `unifi-nas`.** It mounts `nfsvers=3` with `nolock`, so there is no
  byte-range locking — SQLite in particular does not belong there at any speed.
- **Not Longhorn.** Its commit acknowledgement is not backed by a flush.

That leaves `lvm-thin` and `piraeus-r2`. Continue to the next question.

## 3. Does the application replicate the data itself?

If yes — the CNPG clusters do, at the database layer — use **`lvm-thin`**. A
node-local volume per instance is correct there, and it is indistinguishable from
the bare device.

If no, continue.

## 4. Must the Pod stay up when its node reboots?

kured reboots every node on a cycle, and this is often the binding constraint
rather than speed.

- **Yes → `piraeus-r2`.** Two synchronous replicas; the PV's node affinity lists
  both, so the Pod reschedules to the second when the first drains.
- **No → `lvm-thin`**, which pins the Pod to one node. Pair it with real backups:
  losing the node loses the volume.

## 5. Does the Pod need to move freely, beyond two nodes?

**`piraeus-r2-roaming`**, capped at **32 GiB** by admission policy — larger PVCs
are denied. It has never been benchmarked, and a Pod may attach diskless and run
fully remote until auto-diskful converts it after five minutes, so treat its
performance as unknown.

## 6. Is it bulk sequential?

Media, backups, object storage — **`unifi-nas`**. About 100 MiB/s on a single
1 GbE link, which is the link and not the NAS.

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
