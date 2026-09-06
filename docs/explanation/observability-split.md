# Why observability is split by role { .quad-explanation }

The obvious layout is one `monitoring` namespace holding the whole stack —
Prometheus, Alertmanager, Grafana, Loki, the exporters — because that is how the
charts ship and how most clusters end up. This one does not do that.

Instead the split runs along a different seam: **what collects, and what stores**.

| | Where | Components |
| --- | --- | --- |
| **Collectors and exporters** | `platform` | `alloy`, `kube-prometheus-stack`, `blackbox-exporter`, `uptimerobot` |
| **Stores** | `apps` | `datalake-metrics`, `datalake-logs`, `datalake-alerts`, `grafana` |

Not one namespace with everything in it, and not one namespace per *stack* either.
Prometheus and its exporters end up in different layers.

## Why that seam

The two halves fail differently, and depend on different things.

A **collector** is infrastructure. Nothing declares a dependency on `alloy`, but
everything assumes it. It runs on every node, it has no data of its own, and
losing it means losing visibility rather than losing anything. It belongs with the
CNI and the CSI drivers, in the layer that exists before any workload does.

A **store** behaves like a workload, because it is one. It holds data on a
volume, it needs an ingress, it wants backups, it has an upgrade path with
migrations. `datalake-metrics` has a PVC and an ingress; `grafana` has a Postgres
database of its own. Treating those as platform would mean the layer that is meant
to be boring and stable is also the layer with the most state in it.

The practical consequence: an app failing takes down one app, and a store is an
app. Losing `datalake-logs` loses log *ingestion*, not the cluster.

## The chart makes the split visible

`kube-prometheus-stack` is the clearest case. The chart bundles Prometheus,
Alertmanager and Grafana together with the operator and the exporters — and here
**all three are disabled**:

```yaml
prometheus:
  enabled: false
alertmanager:
  enabled: false
grafana:
  enabled: false
```

What is left is the operator, `node-exporter`, `kube-state-metrics` and the
scrape-target plumbing. The chart is used for its collector half and nothing else,
while the stores it would otherwise install run in `apps` with their own
lifecycles.

That is a real cost, and worth naming: a bundled chart is being used against its
grain, so its defaults have to be re-checked after every major to see whether
something re-enabled itself.

## Stores declare how they are read

`datalake-logs` ships its own Grafana datasource as a ConfigMap labelled
`grafana_datasource: "1"`. Grafana does not carry a list of every store it can
read; each store says how to reach it, and Grafana picks that up.

So adding a store is one directory, and removing one does not leave a dangling
datasource in a component that never knew about it.

## Rules live with what produces the signal

There is no central rules directory. 19 `PrometheusRule` files sit in **18
different directories**, next to whatever emits or remediates the thing they alert
on:
`topolvm` and `piraeus-datastore` in storage, `cert-manager` in security,
`system-kured` and `flux-system` in cluster, `sonarr`/`radarr`/`prowlarr` inside
`vod-arr`, `ups` in its own app.

The reasoning is the same as everywhere else on this site: a rule is invalidated
by a change to the thing it watches. Kept next to it, the diff that breaks the
alert is the diff that shows the alert. Kept in a central directory, a component
can be rewritten without anything reminding you its alerts now describe something
that no longer exists.

The exceptions are the two rule sets in `kube-prometheus-stack` itself, which
watch Kubernetes rather than any component here.

## CRDs are the one thing that cannot be layered

`prometheus-operator-crds` is a separate Kustomization in `k8s/bootstrap/`, not in
`platform`, and `platform` `dependsOn` it.

That is not an aesthetic choice. Nearly every component in the cluster ships a
`ServiceMonitor`, `PodMonitor` or `PrometheusRule`, so those CRDs must be
established before the platform layer applies anything at all — and a layer cannot
depend on one of its own members. It also carries `wait: true`, because a CRD that
is applied is not yet established, and `prune: false`, because pruning it would
cascade into deleting every monitor and rule in the cluster.

See [how Flux is layered](flux-layering.md) for the rest of that structure.

## What it costs

The split is not free. Someone looking for "the monitoring stack" has to know it
is nine components across three layers — four collectors in `platform`, four
stores in `apps`, and the CRDs in `bootstrap` — and that the `datalake-*` naming is
a convention rather than anything Kubernetes enforces.

What it buys is that the boring layer stays boring. The components that hold
state, need backups and have migrations are in `apps`, where an outage is scoped
to one thing — and the layer everything else silently assumes contains no
databases at all.
