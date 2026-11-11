# KuredRebootRequired { .quad-howto }

## Meaning

A node has wanted a reboot for over a week. kured reboots nodes by itself inside
its reboot window, so this is not a request to reboot one: it says something has
kept kured from doing so across several windows. The `node` label names the node.

## Impact

The node runs the kernel and libraries it booted with. Fixes that unattended
upgrades already installed are on disk and not in effect —
`/var/run/reboot-required.pkgs` on the node lists the packages waiting.
Workloads are unaffected.

The cause is rarely one node's. A shut gate stops every reboot, so the other
nodes follow as their own upgrades arrive.

## Diagnosis

1. Ask kured on that node. Inside the reboot window it logs its decision every
   period; outside it, it logs nothing.

    ```bash
    kubectl -n platform-cluster logs --tail=20 "$(kubectl -n platform-cluster get pod -l app.kubernetes.io/name=kured --field-selector spec.nodeName=<node> -o name)"
    ```

2. Read the most recent decision.

    | Log line | What is stopping the reboot |
    | --- | --- |
    | `Reboot blocked: N active alerts: [...]` | the safety gate — the alerts it lists are firing |
    | `Reboot blocked: prometheus query error: ...` | the gate cannot reach Prometheus, which kured treats as blocked |
    | `Lock already held: <other-node>` | another node holds the reboot lock |
    | `Error draining <node>: ...` | kured took the lock and cordoned the node, and the drain did not finish in time |
    | `Reboot not required` | nothing — the sentinel is gone and the alert is about to resolve |

3. For a held lock, see who holds it and since when. An empty answer means no
   lock is held.

    ```bash
    kubectl -n platform-cluster get ds kured -o jsonpath='{.metadata.annotations.weave\.works/kured-node-lock}'
    ```

## Mitigation

| Cause | Fix |
| --- | --- |
| The gate is shut by firing alerts | Resolve those alerts: they are the incident, and this alert only measures how long it has lasted. kured then reboots the node in the next window without being told. Every alert on the gate is [a reason a drain cannot succeed](../../explanation/node-reboots.md#the-gate-asks-prometheus), so rebooting by hand around it walks into the failure the gate exists to prevent. |
| The gate cannot reach Prometheus | Restore Prometheus in `datalake-metrics`, or the path to it. Nothing reboots until it answers. |
| The lock is held by a node that is not rebooting | The holder keeps the lock for a while after its own reboot, which is normal. A lock left by an interrupted kured expires after `lockTtl`; to release it now: `kubectl -n platform-cluster annotate ds kured weave.works/kured-node-lock-` |
| The drain keeps failing | A PodDisruptionBudget is refusing an eviction — here, most likely [a Postgres primary with no replica to switch to](../../explanation/node-reboots.md#the-failure). kured uncordons and retries by itself; fix what the budget is protecting. `kubectl get pdb -A` shows which allow no disruptions. |
| Nothing is wrong, the queue is long | Each reboot holds the lock for a while afterwards, so a window fits fewer nodes than it has hours. The window, the hold and the gate's alert list are in [kured's values](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/cluster/system-kured/values.yaml). |

### Rebooting by hand

For when kured itself is what is broken. It does not get a node past a shut
gate safely: the same condition that blocks kured will block or break this
drain. The steps are in
[Drain and reboot a node by hand](../drain-and-reboot-a-node.md).
