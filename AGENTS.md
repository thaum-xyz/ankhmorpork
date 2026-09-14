# Working in this repo

Flux-managed k3s homelab. `k8s/bootstrap/` creates the umbrella Flux resources,
`k8s/platform/` contains infrastructure, and `k8s/apps/` contains workloads.
**Two directories per app, split by who owns them.** `k8s/namespaces/<app>/` is
platform-owned and holds what has to exist before the app can reconcile — the
`Namespace`, the `sync.yaml` that is its Kustomization, and a
`ClusterRoleBinding` where the app needs one. The `GitRepository` that
Kustomization reads and the `flux-reconciler` identity it applies as are not
files: Kyverno generates both from the Namespace's `flux.rbac.thaum.xyz/role`
label (`generate-flux-source`, `generate-flux-reconciler`). `k8s/apps/<app>/` is
what `sync.yaml` reconciles, and is the tenant's. That directory line is the
review boundary.

A platform component works the same way one level up: it is a directory listed
in `k8s/platform/<domain>/kustomization.yaml`, reconciled by the
`platform-<domain>` Kustomization in `k8s/flux/platform/`.

**Which namespace a Kustomization object declares is what decides how much it may
do**, because kustomize-controller resolves `--default-service-account` in the
object's own namespace. One in `flux-system` reconciles as cluster-admin; one in
its app's namespace is confined there. Every app Kustomization now lives in its
own namespace, and `k8s/flux/apps/` and the `apps` umbrella are gone.

**Nothing cluster-scoped may live under `k8s/apps/<app>/`** — that directory is
reconciled by the confined identity, so a `Namespace` or `PersistentVolume` there
fails to apply. Either put it in `k8s/namespaces/<app>/`, which the cluster-admin
`namespaces` Kustomization applies, or give that namespace a
`clusterrolebinding.yaml` so its own reconciler may apply it. `dlna-local`,
`paperless`, `photos`, `plex` and `vod-arr` take the second route, because their
`PersistentVolumes` belong with the app rather than with the namespace.

The cost of the confinement is cross-namespace `dependsOn`:
`--no-cross-namespace-refs=true` forbids an app Kustomization naming
`platform-cluster/platform`, so there is no longer an ordering edge from apps to
platform. On a rebuild an app fails until what it needs exists, and retries.

Moving one needs the target Namespace to carry `flux.rbac.thaum.xyz/role` first,
so that its `GitRepository` and `flux-reconciler` exist, and the move itself is
a delete-and-create — so the
outgoing object must be suspended **and** set `prune: false` in an earlier
commit, or deleting it garbage-collects the app it just handed over.

Changing anything Flux applies: see the `app-deployment` skill in
`.claude/skills/`. It covers proving the render, the rollout order and the traps
that have bitten. Editing `docs/`: see the `docs-authoring` skill there — which
section a page belongs in, what must be generated rather than typed, and how to
lint before pushing.

## Validation

```bash
make validate        # renders every kustomization, checks against schemas + CRD catalog
make validate-flux   # asserts every live Flux Kustomization path exists
```

`make validate` also fails on deprecated Flux API versions. Note both scripts read
**git-tracked** files, so a new manifest is invisible until staged.

Kubeconfig: `~/.kube/clusters/ankhmorpork`.

## Helm chart values

Values live in `values.yaml`, fed in via `configMapGenerator` and `valuesFrom` —
not inline in `spec.values`. Renovate's `helm-values` manager reads `values.yaml`
but cannot see inside a HelmRelease.

## Scripts in `hack/`

Bash by default: a script that runs tools in sequence and checks exit codes is a
bash script. Use Python when it needs a data structure that outlives one pipeline
— grouping, joining or cross-referencing across files — or when it parses
something with no good CLI. Prefer the standard library; `yq -o=json` into `json`
beats adding a dependency.

Never embed one language in another. No Python heredocs in bash, no
`subprocess.run(["bash", "-c", ...])` in Python: pick the language that fits and
write the whole script in it. And no wrapper scripts — the Makefile calls the
real script directly.

## Manifest layout and naming

Keep one Kubernetes object per manifest file. Group distinct components under
their own directories and use type-based names inside them, such as
`operator/repository.yaml`, `operator/release.yaml`, `operator/values.yaml`, and
`gui/deployment.yaml`. If a flat directory genuinely needs qualified filenames,
put the object or artifact type first rather than the component name.

## Suspended components

The last five app Kustomizations are declared suspended in Git, transitionally:
they are being retired so the same objects can be recreated in their apps' own
namespaces. None should outlive that move — the annotation on each carries the
reason.

Nothing else is suspended. Check both the repository and live Flux state before
changing suspension because live state can temporarily diverge during
maintenance.

## Postgres (CloudNativePG)

Every database uses the `cnpg-database` chart from
`oci://ghcr.io/thaum-xyz/helm-charts`; `docs/reference/helm-releases.md` lists them.

Rendered names must match what's live — `postgres-rw` is hardcoded by consumers,
so the chart's fullname is the bare release name and `releaseName` is pinned.
Never copy `install.remediation` from another release: its strategy is *uninstall*,
which on an adopted Cluster deletes it and, through `ownerReferences`, its PVCs.

Backups: `barman_cloud_cloudnative_pg_io_*` metrics are the real signal.
`cnpg_collector_last_available_backup_timestamp` reads **0** for plugin-method
backups, so anything built on it is worthless.

## Observability

Split by role, not by stack. `platform-observability` holds collectors and
exporters only — alloy, kube-prometheus-stack (with its own Prometheus and
Alertmanager disabled), blackbox-exporter, uptimerobot. The stores get their own
namespaces: `datalake-metrics` (Prometheus, Pyrra), `datalake-logs` (Loki),
`datalake-alerts` (Alertmanager, github-receiver), `grafana`.

Operator CRDs come from the `prometheus-operator-crds` HelmRelease in `k8s/crds/`,
applied by the `crds` Kustomization declared in `k8s/bootstrap/` because nearly
every component ships a ServiceMonitor or PrometheusRule. The platform group
dependsOn it. The objects still render into `platform-observability`.

Rules live with whatever produces or remediates their signal, the way k8up,
cnpg and ups rules already do.
