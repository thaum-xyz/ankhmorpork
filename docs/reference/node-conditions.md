# Node conditions { .quad-reference }

Every condition a Node carries, who sets it, and the status it has on a healthy
node. `Ready` and `EtcdIsVoter` are healthy when `True`; every other condition
is healthy when `False`.

List the ones that are not in their healthy state, across all nodes:

```bash
kubectl get nodes -o json | jq -r '.items[] | .metadata.name as $n | .status.conditions[] | select(.status != (if .type == "Ready" or .type == "EtcdIsVoter" then "True" else "False" end)) | "\($n)\t\(.type)\t\(.message)"'
```

## Set by the kubelet, k3s and Cilium

| Condition | Healthy | Set by | Not healthy means |
| --- | --- | --- | --- |
| `Ready` | `True` | kubelet | the kubelet is not posting status, or the node cannot run Pods |
| `MemoryPressure` | `False` | kubelet | available memory is under the eviction threshold |
| `DiskPressure` | `False` | kubelet | the node or image filesystem is under the eviction threshold |
| `PIDPressure` | `False` | kubelet | the node is running out of process IDs |
| `NetworkUnavailable` | `False` | Cilium | the agent on the node has not come up |
| `EtcdIsVoter` | `True` | k3s, on control-plane nodes only | the etcd member is still a learner |

## Set by node-problem-detector

The monitors and their thresholds are in
[node-problem-detector's values](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/cluster/node-problem-detector/values.yaml).
Those marked *here* are defined in that file; the rest ship with the image.

| Condition | Healthy | Read from | Not healthy means |
| --- | --- | --- | --- |
| `KernelDeadlock` | `False` | kernel log | a task hung, or the kernel reported a deadlock |
| `ReadonlyFilesystem` | `False` | kernel log | a filesystem was remounted read-only |
| `XfsShutdown` | `False` | kernel log | an XFS filesystem shut itself down |
| `CperHardwareErrorFatal` | `False` | kernel log | firmware reported a fatal hardware error |
| `FrequentUnregisterNetDevice` | `False` | journal | network devices are failing to unregister, repeatedly |
| `FrequentK3sRestart` | `False` | journal, *here* | `k3s.service` started several times within twenty minutes |
| `UnattendedUpgradeUnhealthy` | `False` | journal, *here* | an `apt-daily` unit failed in the last day |
| `APTLongRunning` | `False` | journal, *here* | an `apt-daily` unit started and has not finished |
| `DRBDDegraded` | `False` | drbd-reactor's metrics on the node, *here* | see [below](#drbddegraded) |

## DRBDDegraded

Evaluated every thirty seconds on each node. A node that has never run a
LINSTOR satellite reads `False`.

It is `True`, with the count in the condition's message, while any of these
holds for a DRBD resource on the node:

| The message says | Meaning |
| --- | --- |
| `devices not UpToDate` | a local replica is `Outdated`, `Inconsistent` or still syncing; `Diskless` is not counted |
| `devices lost their disk` | a replica is diskless without having been made so: the backing disk failed or detached |
| `peers out of sync` | blocks differ from a peer's, which `linstor resource list --faulty` does not show |
| `connections not Connected` | a peer is unreachable |
| `devices without quorum` | the node cannot see enough peers to write |
| `resources suspended` | I/O is frozen |

It is also `True` when the satellite's metrics port does not answer, answers
with a truncated response, or reports no resources at all, which is the state
of a node that has just rebooted.

Both ends of a resync read `True` until it finishes: the replica that is
catching up and the peer it reads from.

No alert is built on this condition. The `drbd*` alerts are, and
[drbdResourceWithNoUpToDateReplicas](../how-to/runbooks/drbdResourceWithNoUpToDateReplicas.md)
covers a replica that does not recover, including
[replacing the older replica](../how-to/runbooks/drbdResourceWithNoUpToDateReplicas.md#replacing-the-older-replica)
of a pair that is connected but out of sync.

## Related

- [Drain and reboot a node by hand](../how-to/drain-and-reboot-a-node.md) —
  the procedure that waits on these
