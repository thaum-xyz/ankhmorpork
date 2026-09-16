# What a database release waits for { .quad-explanation }

A `cnpg-database` HelmRelease reports `Ready` when the Postgres cluster is
ready, not when the manifests have been applied. Helm's waiter has no opinion
about a CloudNativePG `Cluster` — it is a custom resource, and kstatus reports
anything it cannot judge as current. `spec.healthCheckExprs` supplies the
missing judgement as a CEL expression:

```yaml
healthCheckExprs:
  - apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    current: status.conditions.exists(e, e.type == 'Ready' && e.status == 'True')
```

Before this, every one of these releases disabled the waiter outright, so a
change that left a cluster degraded still reported a successful release.

## What the expression deliberately leaves out

Each omission is load-bearing.

| Not written | Why |
| --- | --- |
| `failed:` | A `Failed` resource stops the wait early. CNPG holds `Ready=False` for the whole of a normal rolling update, so a `failed` expression on `Ready` would fail the release seconds into every routine restart. |
| `status.readyInstances == status.instances` | `Ready` is already `False` while an instance is down, so it adds nothing to the case that matters — and it would block on a *fenced* instance, where `Ready` stays `True` because fencing is a deliberate act. Blocking a release on maintenance somebody is in the middle of is the wrong response. |
| `LastBackupSucceeded` | Backup history is not a property of the release. At least one cluster carries a stale `lastSuccessfulBackup`, which would hang every upgrade behind it. |
| `filter(…).all(…)`, the idiom the upstream CEL cheatsheet uses | `all` over an empty list is true, so a Cluster with no conditions yet would read as ready. `exists` states the requirement positively. |

Nothing else in the release needs an expression. The `ExternalSecret`s,
`ObjectStore`, `ScheduledBackup`, `PodMonitor` and `PrometheusRule` carry no
`status.observedGeneration`, so kstatus reports them current at once and the
`Cluster` is the only thing the upgrade actually waits for.

## Install does not wait; upgrade does

`install.disableWait: true` stays. Install remediation defaults to *uninstall*,
which on an adopted `Cluster` deletes it and, through `ownerReferences`, its
PVCs. `uninstall.deletionPropagation: orphan` should prevent that, but it is the
only thing that would, and these clusters are adopted — they do not re-install
in normal operation. Upgrade is the path that runs, so upgrade is the path that
waits.

## A failed wait stalls the release

`upgrade.remediation.retries: 0` is unchanged, so there is no rollback — the
alternative is Helm reverting a database to its previous manifest unattended.
The cost is that one upgrade which does not reach `Ready` inside `timeout` ends
like this:

```
Ready    False  UpgradeFailed    timeout waiting for: [Cluster/<ns>/postgres status: 'InProgress']
Stalled  True   RetriesExceeded  Failed to upgrade after 1 attempt(s)
```

and helm-controller does not try again on its own. Two things clear it: any
change to the HelmRelease spec, which resets the retry counter, or

```bash
flux -n <namespace> reconcile helmrelease <release> --reset
```

`FluxCDReconciliationFailure` covers the state, so a release stuck this way
pages rather than going quiet. It is not free, though — see
[how Flux is layered](flux-layering.md) for where a stalled object stops changes
landing.

## Why the timeout is where it is

`timeout: 10m` has to sit between two numbers: long enough for a real rolling
update, short enough that a slow-but-successful one does not trip
`FluxCDReconciliationFailure`, which fires on 15 minutes of not-Ready and cannot
tell waiting from stuck.

The measurement: on 2026-09-14 every Postgres cluster in the fleet restarted at
once. The slowest went from losing its first instance to `Ready=True` again in
4m23s, and every cluster's `Ready` condition transitioned back at the second its
last instance became ready. That is the worst case the fleet produces, with all
the clusters contending, and it leaves a margin of more than two over.
