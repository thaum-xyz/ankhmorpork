# Working in this repo

Flux-managed k3s homelab. `k8s/bootstrap/` creates the umbrella Flux resources,
`k8s/platform/` contains infrastructure, and `k8s/apps/` contains workloads.
Component Flux Kustomizations live in `k8s/flux/platform/` and `k8s/flux/apps/`.

Changing anything Flux applies: see the `flux-app-change` skill in
`.claude/skills/`. It covers proving the render, the traps that have bitten, and
removing `kustomizeconfig.yaml`.

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

## Suspended components

No Flux Kustomizations are currently declared suspended in Git. Check both the
repository and live Flux state before changing suspension because live state can
temporarily diverge during maintenance.

## Postgres (CloudNativePG)

All eleven databases use the `cnpg-database` chart from
`oci://ghcr.io/thaum-xyz/helm-charts`.

Rendered names must match what's live — `postgres-rw` is hardcoded by consumers,
so the chart's fullname is the bare release name and `releaseName` is pinned.
Never copy `install.remediation` from another release: its strategy is *uninstall*,
which on an adopted Cluster deletes it and, through `ownerReferences`, its PVCs.

Backups: `barman_cloud_cloudnative_pg_io_*` metrics are the real signal.
`cnpg_collector_last_available_backup_timestamp` reads **0** for plugin-method
backups, so anything built on it is worthless.

## Out of scope unless asked

`k8s/apps/monitoring` — still hand-maintained kube-prometheus manifests with the
largest upgrade backlog in the repo. Excluded from routine upgrade work.
