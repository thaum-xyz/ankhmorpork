# Drain and reboot a node by hand { .quad-howto }

kured reboots nodes by itself inside its window. This is for the reboot you
want to watch: after a kernel-module or k3s upgrade, or when kured itself is
what is broken. It does not get a node past
[a shut gate](../explanation/node-reboots.md#the-gate-asks-prometheus) safely:
whatever blocks kured will block or break this drain too.

Do one node at a time, and start outside kured's reboot window — `rebootDays`,
`startTime` and `endTime` in
[kured's values](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/cluster/system-kured/values.yaml).

## What the drain does to each Pod

Storage decides it; the classes are in
[Storage classes](../reference/storage-classes.md#mobility-and-access-modes).

| The Pod has | During the drain | It is back |
| --- | --- | --- |
| no volume, `unifi-nas`, or `piraeus-r2-roaming` | rescheduled on another node | at once |
| `piraeus-r2` | rescheduled only if the other replica holder can take it, otherwise `Pending` | at once, or after the uncordon |
| `lvm-thin` | `Pending` — the volume is on this node's disks | after the uncordon |
| a Postgres instance | the primary role moves to a replica elsewhere; the Pod itself is `Pending` | after the uncordon |

A Postgres primary is the one thing an eviction cannot move: its
`<name>-primary` PodDisruptionBudget allows no disruption. The drain cordons
the node before it evicts anything, the CloudNativePG operator takes the cordon
as its signal to
[switch every primary on the node away](../explanation/node-reboots.md#the-failure),
and the eviction goes through once the Pod is no longer the primary. Nothing
has to be done by hand for that.

## Steps

1. **Check that the cluster can lose a node.** Every node is `Ready` and none
   is `SchedulingDisabled`; every Postgres cluster reads
   `Cluster in healthy state` with all its instances ready.

    ```bash
    kubectl get nodes && kubectl get clusters.postgresql.cnpg.io -A
    ```

2. **Check that no piraeus volume is short of a replica.** The list must be
   empty, whichever node you are rebooting.

    ```bash
    kubectl -n platform-storage exec deploy/linstor-controller -- linstor resource list --faulty
    ```

3. **[Silence the node's alerts](silence-alerts-for-maintenance.md)** for an
   hour, with the `node` and `instance` matchers.

4. **Drain the node.** It returns once every Pod is gone, the switchovers
   included.

    ```bash
    kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=20m
    ```

5. **Reboot.**

    ```bash
    ssh <node> sudo systemctl reboot
    ```

6. **Wait for `Ready`.** If your kubeconfig names this node as its server,
   `kubectl` times out until the node is back.

    ```bash
    kubectl get node <node> --watch
    ```

7. **On a node that holds piraeus replicas, wait for them to resync.** The
   list must be empty again before anything else happens. A replica that stays
   `Outdated` is
   [drbdResourceWithNoUpToDateReplicas](runbooks/drbdResourceWithNoUpToDateReplicas.md)
   in the making; follow that page and promote nothing before its comparison
   step.

    ```bash
    kubectl -n platform-storage exec deploy/linstor-controller -- linstor resource list --faulty
    ```

8. **Uncordon.** Do it as soon as the node is healthy: a node left cordoned
   fires `NodeUnschedulable`, which shuts kured's gate for every other node.

    ```bash
    kubectl uncordon <node>
    ```

9. **Wait for what was `Pending` to return.** The Postgres replicas rejoin
   and each cluster reports all its instances ready; nothing is left
   `Pending`.

    ```bash
    kubectl get clusters.postgresql.cnpg.io -A && kubectl get pods -A --field-selector=status.phase=Pending
    ```

10. **Expire the silences.**

    ```bash
    amtool silence expire <silence-id>
    ```

For the next node, start again from step 1. The primaries do not move back:
[they converge](../explanation/node-reboots.md#what-this-does-not-solve) on the
nodes still waiting their turn, so the last node has the most switchovers to
make.

On 2026-11-11 the drain of `beelink01` returned in under a minute, and each
Postgres cluster it moved was without a primary for under ten seconds. The
piraeus replicas on `beelink01` and `beelink02` were back in sync about two
minutes after each node was `Ready`. What takes longest is everything the drain
rescheduled starting up elsewhere, which has no bearing on when the node can be
rebooted.

## A drain that does not finish

A budget is refusing an eviction, and `kubectl get pdb -A` shows which allow
none. The drain leaves the node cordoned when it times out; uncordon it before
doing anything else.

| The budget is | What it means |
| --- | --- |
| `<name>-primary`, owned by a Postgres cluster | That cluster has no replica it can switch to: none is ready and streaming on a schedulable node. Repair the cluster first. |
| an application's | [`validate-pdb-drain-safety`](../reference/admission-policies.md#validate-pdb-drain-safety) warns on a budget that allows no voluntary disruption, or that lets an unhealthy Pod hold an eviction. It only warns, so one that ignored the warning can still block. Fix the budget; do not force the drain. |

The switchovers depend on the CloudNativePG operator and its barman plugin
being reachable while the node empties, which is why both run two replicas on
different nodes — the reason is in
[the plugin's values](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/storage/cnpg-system/barman/values.yaml).
With either at one replica, cordon the node and wait for every cluster to read
healthy again before draining it.

## Handing the node back to kured

There is nothing to hand back. The reboot removes `/var/run/reboot-required`,
so kured stops wanting the node and its `kured_reboot_required` metric drops to
zero.

```bash
ssh <node> ls /var/run/reboot-required
```

If the work will overlap the reboot window, take kured's lock before you start,
so that it reboots nothing while you do. The lock does not expire.

```bash
kubectl -n platform-cluster annotate ds kured weave.works/kured-node-lock='{"nodeID":"manual"}'
```

Release it when the last node is back, or kured reboots nothing again:

```bash
kubectl -n platform-cluster annotate ds kured weave.works/kured-node-lock-
```

!!! warning "The lock does not stop the soft drain"

    Inside the window, every node that wants a reboot and finds the lock held
    takes the [`thaum.xyz/kured-node-reboot`](../reference/annotations.md)
    taint, and the operator moves primaries off tainted nodes. A node whose
    replicas all sit on tainted nodes then has nowhere to switch to, and its
    drain hangs. Drain outside the window, or remove the taint from the other
    nodes first — kured puts it back at its next poll.

## Related

- [How a node reboot is gated](../explanation/node-reboots.md) — what kured,
  the descheduler and the operator each do, and why
- [KuredRebootRequired](runbooks/KuredRebootRequired.md) — finding out why
  kured has not rebooted a node
