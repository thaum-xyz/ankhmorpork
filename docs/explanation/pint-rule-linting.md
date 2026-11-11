# Why the rule linter alerts on change, not on count { .quad-explanation }

[pint](https://cloudflare.github.io/pint/) lints the alerting and recording rules
this cluster runs. It found six alerts that could never have fired, some of them
years old. It also reports a permanent floor of findings that are not defects,
which is why the alert built on it compares **sets** rather than counting.

## It lints what Prometheus loaded, not what is in git

This is the whole reason it earns its keep.

CI lints the `PrometheusRule` objects committed to this repository. That misses
every rule that arrives inside a Helm chart — the `CNPG*` alerts across every
database release in
[Helm releases](../reference/helm-releases.md), Loki's, Piraeus's, and every rule
kube-prometheus-stack's mixins generate. **Most of what Prometheus loads is
therefore invisible to CI**, by an order of magnitude and widening: each new
chart brings its own rules, and none of them lands in git.

So pint also runs in-cluster, as its own Deployment in `datalake-metrics`, with a
`k8s-sidecar` mirroring every ConfigMap the prometheus-operator generates into a
shared volume. It lints the live rule set and queries the live Prometheus, which
is the only way to catch a rule whose selector matches nothing.

!!! info "A rule that matches nothing looks exactly like a healthy one"

    Prometheus does not complain about an alert whose query returns no series. It
    evaluates it, gets nothing, and moves on — for years if nobody looks. Every
    dead alert found here was syntactically valid and passed CI.

## What it found

Six alerts that could not fire, each for a different reason:

| alert | why it could never fire |
| --- | --- |
| `PrometheusNotificationQueueRunningFull` | `queue_length` carries an `alertmanager` label, `queue_capacity` does not, so the comparison never matched |
| `HighlyAvailableWorkloadIncorrectlySpread` | errored on *every* evaluation — a pod with two PVCs made the join ambiguous |
| `ReconciliationFailure` | `gotk_reconcile_condition` was removed from Flux; 19 other `gotk_*` families still existed, so the scrape looked healthy |
| `etcdHighNumberOfFailedGRPCRequests` | killed by our own `keep etcd_.*` relabeling, which dropped etcd's own gRPC metrics |
| `K8upJobFailed` | joined on `kube_job_labels`, which had no series at all |
| `K8upBackupStale` | the same join |

The last two are the reason the accepted-findings set is kept narrow. Backups are
the entire point of those alerts, and a failed backup job produced no alert, no
issue, and no signal of any kind.

Four more — the `KubeStateMetrics*` alerts — had no metric because
kube-state-metrics' telemetry port was never scraped. They are the only alerts
that fire when the exporter stops seeing the API server; in that failure every
other `kube_*` alert simply goes quiet, which is indistinguishable from a healthy
cluster.

## The floor is not a backlog

Most remaining findings describe a quiet cluster, not a broken rule:

- `KubeHpaMaxedOut` reports no series because there are no HorizontalPodAutoscalers.
- `MultipleContainersOOMKilled` waits on `reason="OOMKilled"`, which appears when
  something is OOM-killed.
- A Pyrra ratio SLO with no errors to count records nothing at all — `sum(rate(…{code=~"5.."}))`
  over an empty selector returns *no series*, not zero. An SLO returns to that
  state whenever the process that counted its last error restarts.

**Driving the count to zero would mean disabling alerts that work.** The findings
are correct; the conditions they describe have not happened.

Two of pint's four wordings are therefore accepted in its config and stop being
reported. Both are cases where the metric exists and only a label value is
missing, so a typo would still surface — under the third wording, *"didn't have
any series for"*, which is **never** accepted. That is the wording
`K8upJobFailed` was reported under.

The fourth wording, *"no series with the … label"*, is accepted for one rule.
`KubeJobNotCompleted` ends in an opt-out on
`kube_job_labels{label_excluded_from_alerts="true"}`, and kube-state-metrics adds
a `label_*` label only to objects that carry the key — so for as long as no Job
opts out, the label is missing from every series. A misspelt label name reads the
same way, which is why this is one exception and not a class. The spelling is
checked against claims, where the same
[`excluded_from_alerts`](../reference/annotations.md#excluded_from_alerts) key
does match.

That rule was first reported under the third wording. A chart upgrade added the
clause, `jobs` was not in kube-state-metrics' labels allowlist, and the opt-out
could not have worked for anyone who used it. The exception rests on that
allowlist entry: without it the same block would hide the third wording.

## Why the alert compares sets

`max(pint_problems) > 0` was permanently true given a floor, so it never cleared
and held one GitHub issue open indefinitely.

A delta would not have been enough either. **pint shows one problem per group and
hides the duplicates** — roughly half of all findings at any time. The day the
accepted set landed, the total fell **37 → 15** while `KubeContainerWaiting`
appeared underneath. A count-based alert would have seen a drop and said nothing.

```promql
count by (name, reporter) (pint_problem{job="pint"})
unless
count by (name, reporter) (last_over_time(pint_problem{job="pint"}[24h] offset 2h))
```

Aggregating to `(name, reporter)` is required rather than tidy: `problem` embeds
durations that change every run, `filename` embeds the rule's UID, and the scrape
adds `pod` and `instance` — so a pint rollout alone would mark every finding new.

It accepts one limitation: a rule that breaks a *different* way keeps the same
`(name, reporter)` and does not re-alert. `K8upJobFailed` moving from a dead join
to an intermittent metric is exactly that, and staying quiet is right — the rule
did not newly break.

A finding has to last an hour before the alert fires, because a node reboot
produces findings that do not. pint words a series as "only sometimes present"
when its selector matches nothing as pint looks and the series
already has a gap in the last week. One reboot leaves the gap; the next empties
the selector until the Pods it moved are back, and pint reports whatever was
restarting. Those findings are gone within one drain and one lint.

The alert is short-lived by construction. The baseline is offset by two hours, so
it catches up two hours after a finding appears and the alert resolves, fixed or
not. The 24h is how far back the baseline looks, not how long the alert fires: a
finding that goes away and comes back within a day is not new again.

**Resolving is therefore not a signal.** The finding is still in `pint_problem`,
and the issue the alert opened stays open, because the GitHub receiver does not
close issues for resolved alerts. Close it when the finding is gone or accepted.

## Judge it by which findings changed

The count moves for reasons that are nobody's fault. It rose when k8up arrived
with alerts whose metrics had no series yet, and again when new Pyrra SLOs landed
whose burn-rate records have seen no errors. Neither is a regression.

!!! tip "The one habit worth keeping"

    **Diff the finding names between runs. Never compare totals.** That is what
    the alert now does, so the discipline is enforced rather than remembered.

## Silencing a finding means silencing a family

pint's config cannot disable a check for a single metric —
`promql/series(kube_job_labels)` is rejected as an unknown check name, and that
syntax only works as a comment inside the rule file, which chart-generated rules
cannot carry. Every exception therefore disables the check for the whole rule.

Worse, because duplicates are hidden, **silencing the name pint printed just
promotes the next one**. That happened six times:

```
KubeQuotaAlmostFull             -> KubeQuotaFullyUsed -> KubeQuotaExceeded
KubePersistentVolumeFillingUp   -> KubePersistentVolumeInodesFillingUp
one Pyrra burn-rate window      -> the other six
KubePodCrashLooping             -> KubeContainerWaiting
KubePersistentVolume.+FillingUp -> matched only the Inodes variant; `.*`, not `.+`
a rule rewrite                  -> K8upJobFailed onto an already-accepted metric
```

Ask **which other rules read the same metric**, match the family with a regex,
then re-lint to confirm. Repeat it after a rule is *rewritten*, not only after one
is accepted — the last row is a rewrite that made an alert a co-reader of a metric
already excepted.

## Reading it

pint has no UI. Its findings are on its own `/metrics`:

```promql
count by (reporter) (pint_problem)
pint_problem{reporter="promql/series"}   # then read the `problem` label
```

!!! warning "Three ways pint looks stale"

    - **Nothing is published for the first ~4 minutes.** No `pint_problem` series
      exist until the first check iteration completes; the family is absent, which
      reads exactly like "no problems". Check `pint_check_iterations_total`.
    - **It lints on its own ~10m interval**, not when a rule file changes.
    - **It caches its Prometheus queries**, so a *fresh* lint can serve a stale
      answer. After a change that restores a metric, allow two iterations.

    pint also reads its own configuration only at startup, which is what
    [ConfigMap autoreload](configmap-autoreload.md) exists to handle — it once ran
    a stale config for six hours.
