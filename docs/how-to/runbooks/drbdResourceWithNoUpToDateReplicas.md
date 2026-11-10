# drbdResourceWithNoUpToDateReplicas { .quad-howto }

## Meaning

A DRBD resource has had no replica in `UpToDate` for a minute. The `name` label
is the resource, which is also the name of the PersistentVolume. A piraeus
volume keeps [two replicas](../../reference/storage-classes.md#piraeus-r2-and-piraeus-r2-roaming)
and a diskless tiebreaker; this says neither replica is one DRBD will serve
from.

`drbdDeviceNotUpToDate` fires beside it, once per replica, and its
`drbd_device_state` label says what each replica is instead.

## Impact

The volume cannot be mounted. Its Pods stay in `ContainerCreating` with
`failed to set source device readwrite`, and they stay there: between two
replicas that are both `Outdated`, DRBD does not pick one. The data is still on
disk on both nodes.

Two things queue behind it for as long as it fires. kured reboots no node,
because [its gate](../../explanation/node-reboots.md#the-gate-asks-prometheus)
treats every firing `drbd` alert as a reason a drain cannot succeed. And K8up
starts no further backup in that namespace while the one waiting for this
volume is unfinished.

## Diagnosis

1. List what LINSTOR considers faulty: the nodes holding the resource, the
   state of each replica, and whether its connections are `Ok`.

    ```bash
    kubectl -n platform-storage exec deploy/linstor-controller -- linstor resource list --faulty
    ```

2. Find the claim the volume belongs to.

    ```bash
    kubectl get pv <resource> -o jsonpath='{.spec.claimRef.namespace}/{.spec.claimRef.name}{"\n"}'
    ```

3. Ask DRBD on each node that holds a replica. `disk:` is that replica's state
   and `open:` whether anything has it mounted. `size:` is the data area in KiB
   and `backing_dev:` the volume underneath; step 5 needs both. Each peer is
   listed with its `node-id` and the state of the link to it.

    ```bash
    kubectl -n platform-storage exec "$(kubectl -n platform-storage get pod -l app.kubernetes.io/component=linstor-satellite --field-selector spec.nodeName=<node> -o name)" -c linstor-satellite -- drbdsetup status <resource> --verbose --statistics
    ```

4. Read what DRBD decided when the replicas last met, on the node that rebooted
   most recently. The kernel log is the only record of it and does not survive
   that node's next reboot, so save the output.

    ```bash
    kubectl -n platform-storage exec "$(kubectl -n platform-storage get pod -l app.kubernetes.io/component=linstor-satellite --field-selector spec.nodeName=<node> -o name)" -c linstor-satellite -- sh -c 'dmesg -T | grep <resource>'
    ```

5. Compare the replicas byte for byte: run this on both nodes and compare the
   two sums. Do it only while step 3 shows `open:no` on every node, and check
   that again afterwards — a mount in between changes the data under the sum.
   A sum beginning `e3b0c442` is the sum of no data at all: the size or the
   path is wrong, and two of those match each other.

    ```bash
    kubectl -n platform-storage exec "$(kubectl -n platform-storage get pod -l app.kubernetes.io/component=linstor-satellite --field-selector spec.nodeName=<node> -o name)" -c linstor-satellite -- sh -c 'head -c $((<size> * 1024)) <backing_dev> | sha256sum'
    ```

6. If the sums differ, find the newer replica. On XFS it is the one whose
   journal `head` is further on.

    ```bash
    kubectl -n platform-storage exec "$(kubectl -n platform-storage get pod -l app.kubernetes.io/component=linstor-satellite --field-selector spec.nodeName=<node> -o name)" -c linstor-satellite -- sh -c 'xfs_logprint -t <backing_dev> | grep "log tail"'
    ```

7. Match what you found.

    | Steps 1 and 3 show | Steps 5 and 6 show | Cause |
    | --- | --- | --- |
    | a satellite that is not `Online`, or a link that is not `Connected` | — | The replica that could be `UpToDate` is out of reach, not lost. |
    | a replica that is `Inconsistent` | — | A resync was interrupted and its source is the replica out of reach. |
    | both replicas `Outdated`, every link `Connected` | the same sum | DRBD could not tell which replica was current when they reconnected. Both are. |
    | both replicas `Outdated`, every link `Connected` | different sums | The same, and a resync that was due did not run. One replica is older. In step 4 it reads `Resync ... skipped` and then `cleared bm UUID and bitmap`. |

!!! danger "Compare before promoting"

    `out-of-sync:0` and equal generation identifiers do not show that two
    replicas match. On 2026-10-12 DRBD reported both for a volume whose
    replicas differed, after dropping its own record of what was out of sync
    ([the record of that incident](https://github.com/thaum-xyz/ankhmorpork/issues/1610#issuecomment-6774610016)).
    Promoting without step 5 can leave the older copy as the one that survives.

## Mitigation

| Cause | Fix |
| --- | --- |
| A replica is out of reach | Bring the node or the link back. DRBD resyncs by itself and the alert resolves; promote nothing. |
| A resync was interrupted | The same. An `Inconsistent` replica is a partial copy and must never be promoted. If its source is gone for good, the data has to come from [the K8up repository](../../explanation/app-backups.md). |
| Both replicas are current | [Declare one current](#declaring-a-replica-current), on either node. |
| One replica is older | [Replace the older replica](#replacing-the-older-replica). |

### Declaring a replica current

1. Promote the replica and demote it again. That is enough to mark it
   `UpToDate`; the Pod promotes it for real when it mounts.

    ```bash
    kubectl -n platform-storage exec "$(kubectl -n platform-storage get pod -l app.kubernetes.io/component=linstor-satellite --field-selector spec.nodeName=<node> -o name)" -c linstor-satellite -- sh -c 'drbdsetup primary <resource> --force && drbdsetup secondary <resource>'
    ```

2. Repeat step 3 of the diagnosis on both nodes. Each must show `disk:UpToDate`
   and the other as `replication:Established peer-disk:UpToDate`.

3. If one node shows the other in `WFBitMapS` instead, reconnect that link from
   the node that shows it. Seen on 2026-11-10: the link stayed that way and
   writes did not reach the other replica until it was reconnected.

    ```bash
    kubectl -n platform-storage exec "$(kubectl -n platform-storage get pod -l app.kubernetes.io/component=linstor-satellite --field-selector spec.nodeName=<node> -o name)" -c linstor-satellite -- sh -c 'drbdsetup disconnect <resource> <peer-node-id> && drbdsetup connect <resource> <peer-node-id>'
    ```

### Replacing the older replica

Declaring the newer replica current is not enough here: DRBD believes the two
match, so the older one would be marked `UpToDate` as it is.

1. Note the storage pool the replicas are in.

    ```bash
    kubectl -n platform-storage exec deploy/linstor-controller -- linstor volume list -r <resource>
    ```

2. Delete the older replica. This is the step that cannot be undone. LINSTOR
   removes the tiebreaker with it and brings it back in step 4.

    ```bash
    kubectl -n platform-storage exec deploy/linstor-controller -- linstor resource delete <older-node> <resource>
    ```

3. [Declare the newer replica current](#declaring-a-replica-current), on its
   node. It has no peer left, so there is no link to check.

4. Create the replica again. It resyncs in full from the newer one.

    ```bash
    kubectl -n platform-storage exec deploy/linstor-controller -- linstor resource create <older-node> <resource> --storage-pool <pool>
    ```

### Afterwards

Pods mount the volume at kubelet's next retry, without being restarted, and the
first mount replays the filesystem journal. The alert resolves once step 1 of
the diagnosis lists nothing, and kured reboots again in its next window.

A Pod can stay in `ContainerCreating` all the same. A K8up backup Pod created
during the outage holds the volume on its own node until it finishes, and when
it also waits for a second volume that an app Pod holds elsewhere, neither
moves. Delete that Backup; the schedule makes the next one.

```bash
kubectl -n <namespace> delete backups.k8up.io <backup>
```
