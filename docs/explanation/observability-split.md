# Why observability is split by role { .quad-explanation }

The obvious layout is one `monitoring` namespace holding the whole stack —
Prometheus, Alertmanager, Grafana, Loki, the exporters — because that is how the
charts ship and how most clusters end up. This one does not do that.

The split runs along a different seam: **what collects, and what stores**.

| | Layer | Components |
| --- | --- | --- |
| **Collectors and exporters** | `platform` | `alloy`, `kube-prometheus-stack`, `blackbox-exporter`, `uptimerobot` |
| **Stores** | `apps` | `datalake-metrics`, `datalake-logs`, `datalake-alerts`, `grafana` |

## The reason is the word "datalake"

These stores are not meant to be ankhmorpork's monitoring. They are meant to be
*the* store, for more sources than this cluster — which is why they are named
`datalake-*` rather than `monitoring`, and why they sit in `apps` as services that
happen to run here rather than in `platform` as this cluster's own machinery.

Collectors are the opposite. `alloy` runs on every node *of this cluster* and
scrapes *this cluster*; it belongs to ankhmorpork the way the CNI does. A second
environment — [lancre][l] or [uberwald][u] — would bring its own collectors, and
they would be that cluster's platform layer, not this one's.

[l]: https://github.com/thaum-xyz/lancre
[u]: https://github.com/thaum-xyz/uberwald

So the seam is not aesthetic. It is the line along which the other sources attach:
their collectors *there*, pointing at the same stores *here*, with nothing in the
store layer needing to move or be renamed. Had the stack been assembled as one
`monitoring` namespace, that would be a migration rather than an addition — and a
migration with data already in it.

!!! note "Waiting on the refactor, not on a decision"

    Every sample in these stores comes from ankhmorpork today, and the receiving
    side still shows it: Loki runs `auth_enabled: false`, no remote-write receiver
    is enabled, and both `datalake-metrics` and `datalake-alerts` sit on `private`
    ingresses.

    That is sequencing, not uncertainty. The other collectors are ready and are
    held until the cluster refactor currently in flight lands — which is also why
    the store layer is worth reading as the finished shape rather than as a
    placeholder.

A secondary benefit falls out of the same split, and it is worth noting because it
is what keeps the arrangement sensible even before a second cluster exists: stores
behave like workloads — a volume, an ingress, backups, migrations, and in
`grafana`'s case a Postgres of its own — while collectors hold no data at all.
Keeping the stores out of `platform` means the layer everything silently assumes
contains no databases.

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
scrape-target plumbing — the collector half, all of it specific to this cluster.
The stores the chart would otherwise install run in `apps` with their own
lifecycles, because they are not this cluster's to own.

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

What it buys is a store layer that does not have to be rearranged when the other
collectors arrive — which is the near-term plan, not a hypothetical — and, along
the way, a platform layer with no databases in it.

The indirection is the whole point: it is paid once, now, instead of as a
migration later with data already in the stores.
