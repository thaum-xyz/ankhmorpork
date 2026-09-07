# How a node reboot is gated { .quad-explanation }

A kured reboot is not one component's decision. kured, the descheduler, the
CloudNativePG operator and Prometheus hand work to each other through a node
taint and a list of alert names, and the handoff is deliberate: each does the
part the others cannot.

The shape was settled by a failure on 2026-09-07, so this page starts there.

## The failure

kured cordoned a node while another was already cordoned, and then spent two
hours failing to drain it.

Every CloudNativePG cluster carries a `<name>-primary` PodDisruptionBudget whose
`disruptionsAllowed` is **permanently zero**. That is not a misconfiguration. A
drain of the primary's node succeeds only because the operator switches the
primary away first, and the budget then follows it to the new node. The budget
exists to make sure nothing evicts a primary that has nowhere to go.

The operator will only switch over to a replica that is ready, streaming, and on
a **schedulable** node. With one node already cordoned, several clusters had no
such candidate. So the budgets held — correctly — and the drain had nothing to do
but wait.

That produced a loop that could not exit on its own:

1. Two nodes unavailable meant replicas could not be placed.
2. Unplaceable replicas meant degraded clusters, whose budgets allowed nothing.
3. Blocked budgets meant the drain could never finish.
4. The reboot that would have returned the capacity was the thing being blocked.

It cleared only when a node became schedulable again by hand.

## What the reboot loop could not answer

Nothing here is new machinery. Every knob already existed and was simply off.

| Question | Answer before | Answer now |
| --- | --- | --- |
| Is the cluster healthy enough to lose a node? | never asked | six alerts must be quiet |
| How long is a drain allowed to fail? | two hours | twenty minutes |
| Does anything move before the drain? | no | the descheduler and the operator both do |

### The gate asks Prometheus

kured can query `ALERTS` and refuse to start while any named alert is active.
The subtle part is `alertFilterMatchOnly`, which **inverts** the regexp: without
it the pattern is a mute-list of alerts to ignore, with it the pattern is an
allow-list of alerts that block. The same string means opposite things depending
on one boolean, and only one of those meanings is safe to run.

The list is not "important alerts". It is exactly *reasons a drain cannot
succeed*: a node that is down, a node that is cordoned, a Postgres primary with
no replica to switch to, DRBD replicas still resyncing. A backup failure is
serious and does not belong here, because it does not make a drain hang.

Two of those alerts did not exist and were written for this. They live with the
component that produces their signal rather than with kured, which means the
gate depends on alert **names** defined in three other places. Renaming one does
not fail: kured simply stops checking. Both rules carry a comment saying so, and
the regexp names the file each alert comes from.

The gate is deliberately fail-safe. If Prometheus cannot be reached, kured treats
that as blocked and reboots nothing.

### A shorter timeout is the safer one

Cutting the drain timeout from two hours to twenty minutes looks like giving up
sooner on a hard problem. It is the opposite.

A drain that has not finished in twenty minutes is blocked by a budget and will
not finish; the remaining time is spent holding a cordon on a node the cluster
still needs. And timing out is cheap, because kured is configured not to force
the reboot: on failure it releases the lock, uncordons the node it had cordoned,
and tries again later. The expensive outcome was never the timeout. It was the
cordon that outlived it.

The same reasoning applies to the poll interval, which is *also* the retry
interval. At two hours, a node that lost one race for the lock did not ask again
until the reboot window had moved on.

### The soft drain helps less than it looks, for a good reason

kured taints a node [`thaum.xyz/kured-node-reboot`](../reference/annotations.md)
as soon as it wants a reboot and finds the lock held. Two components watch for
it, and they reach different workloads.

The descheduler moves Pods it can place elsewhere. Which Pods those are is
decided entirely by storage: a volume that follows its Pod can move, and a volume
pinned to one node's disks cannot. That makes the protection list a
[storage-class](../reference/storage-classes.md) question rather than a workload
one — and it is why protecting *every* Pod with a claim, the obvious setting,
made the soft drain do nothing at all.

Every Postgres instance sits on node-local storage, so the descheduler can never
move one. That is not a gap to close. A database instance is not relocated by
eviction; the operator moves the *primary role* by switching over, leaving the
data where it is. So the operator is told to treat the same taint as a drain
signal, and does its switchovers while the node is still queued rather than after
it has been cordoned and the drain is already blocking.

This is worth stating plainly because it inverts the intuition: the stateless
half of the cluster is drained by eviction, and the stateful half is drained by
promotion. Only one of those is the descheduler's job.

## The order things happen in

| Stage | Who acts | What changes |
| --- | --- | --- |
| Reboot needed, lock held elsewhere | kured | node is tainted `PreferNoSchedule` |
| Taint appears | CloudNativePG | primaries switch off the queued node |
| Taint appears | descheduler | Pods with movable volumes are evicted |
| Lock acquired | kured | the six alerts are checked |
| Gate clear | kured | cordon, drain, reboot, uncordon |
| Reboot done | kured | lock held a while longer, then released |

The final hold is what paces the cluster: the next node cannot start until it
expires, so a reboot window fits fewer nodes than it has hours for. That is a
choice, not a limit. Reboots happen on several days a week, and a node that waits
until the next window has lost nothing.

## What this does not solve

**The first node gets no head start.** The taint is applied only to nodes that
find the lock *already held*, so whichever node wins it goes straight to cordon
and drain, and its databases switch over during the drain rather than before it.
kured's `drainDelay` is not a fix — it sleeps before the cordon, so nothing
downstream has been told anything yet.

**A blocked reboot is invisible in metrics.** kured exposes no counter for it.
The evidence is in its logs, and eventually in `KuredRebootRequired`, which fires
when a node has wanted a reboot for long enough to have missed several windows.
That alert is the backstop for a gate stuck shut — a chronically firing storage
alert, or an unreachable Prometheus — and there is nothing else watching.

**Primaries converge.** Switchover only ever moves a primary to a node that is
not cordoned or tainted, so as nodes reboot in turn the primaries pile onto
whichever ones are left. The pile disperses as the remaining nodes reboot. It is
a fair objection to the design and the answer is that the alternative — moving
primaries onto nodes that are about to go down — is worse.

## Related

- [How Flux is layered](flux-layering.md) — reconciling these components in the
  wrong order reports success while using stale values
- [Annotations and labels](../reference/annotations.md) — the taint's contract
- [Storage classes](../reference/storage-classes.md) — which volumes follow their
  Pod, which do not
- [Why storage is split the way it is](storage-durability.md) — why the databases
  are on node-local disks in the first place
