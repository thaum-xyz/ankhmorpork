# Working in this repo

Flux-managed k3s homelab. `core/` bootstraps the cluster, `base/` is infrastructure,
`apps/` is workloads. Every component has a Flux Kustomization in
`base/flux-apps/<name>.yaml`.

## Validation

```bash
make validate        # renders every kustomization, checks against schemas + CRD catalog
make validate-flux   # asserts every live Flux Kustomization path exists
```

`make validate` also fails on deprecated Flux API versions. Note both scripts read
**git-tracked** files, so a new manifest is invisible until staged.

## Helm chart values

Values live in `values.yaml`, fed in via `configMapGenerator` and `valuesFrom` —
not inline in `spec.values`. Two reasons: Renovate's `helm-values` manager reads
`values.yaml` but cannot see inside a HelmRelease, and 33 of 34 releases already
do it this way.

New components should set `generatorOptions.disableNameSuffixHash: true` and skip
`kustomizeconfig.yaml`. helm-controller detects value changes through
`status.lastAttemptedConfigDigest`, so the hash suffix isn't needed, and without it
there's no generated name for `nameReference` to rewrite — which is all
`kustomizeconfig.yaml` does. Older components still carry it; that's historical.

With the hash disabled, ConfigMap names must be unique per namespace. Most apps
already generate one called `values`, so name others distinctly
(e.g. `postgres-values`). Trade-off: a values edit no longer changes the
HelmRelease spec, so it applies at the next reconcile rather than instantly —
`flux reconcile hr <name> -n <ns>` forces it.

## Verifying against the cluster

Kubeconfig: `~/.kube/clusters/ankhmorpork`.

**Build the parent kustomization, not a subdirectory.** The namespace is injected
by the parent, so building `db/` alone yields namespace-less objects that
`kubectl diff` compares against `default` — reporting every object as new with a
full spec body. Alarming and meaningless. Same for `helm template`: pass
`-n <namespace>`.

**`flux diff` only sees what a Kustomization applies**, not what Helm renders from
a HelmRelease. Use [`flux-build`](https://github.com/DoodleScheduling/flux-build)
for the full chain. `core` needs `--api-versions monitoring.coreos.com/v1`;
components taking values from a runtime Secret can't be rendered offline.

**`flux diff` ignores `kustomize.toolkit.fluxcd.io/prune: disabled`.** It computes
deletions from inventory-versus-build, so protected objects show as `deleted`. The
annotation does work — verified empirically. Don't panic at that output.

## Suspended components

Roughly half the fleet is suspended, declared in git. This is deliberate: leftovers
from emergency work in Dec 2025 when nodes failed and reconciliation was stopped to
allow manual edits. Some were *already failing* before suspension, so **don't
resume one without reading why it stopped** — check its HelmRelease conditions
first. `flux-apps` itself is the exception: never declare `suspend` on it, since it
manages its own definition and would re-suspend itself on resume.

## Postgres (CloudNativePG)

Databases use the `cnpg-database` chart from
`oci://ghcr.io/thaum-xyz/helm-charts`. Migrating a hand-written bundle onto it is
**data-destructive if rushed**: PVCs are held by `ownerReferences` on the Cluster,
and `lvm-thin` is `reclaimPolicy: Delete` on node-local single-copy storage.

Sequence, as separate PRs — one state per merge:

1. Add `kustomize.toolkit.fluxcd.io/prune: disabled` to every object, plus
   `helm.sh/resource-policy: keep` on the Cluster and ObjectStore. Metadata only.
   Must reconcile before step 3, or the protection never exists when needed.
2. Out of band: flip the PVs to `reclaimPolicy: Retain`, take a backup, confirm it
   reaches `completed`.
3. Replace the manifests with `release.yaml` + `values.yaml`. Never copy
   `install.remediation` from another release — its strategy is *uninstall*, which
   on an adopted Cluster deletes it and its PVCs.
4. Drop the prune annotation via a values change.

Helm adopts existing objects without ownership metadata: `disableTakeOwnership`
defaults to false. Rendered resource names must match what's live — `postgres-rw`
is hardcoded by consumers, so the chart's fullname is the bare release name.

Backups: `barman_cloud_cloudnative_pg_io_*` metrics are the real signal.
`cnpg_collector_last_available_backup_timestamp` reads **0** for plugin-method
backups, so anything built on it is worthless.

## Out of scope unless asked

`apps/monitoring` — still hand-maintained kube-prometheus manifests with the
largest upgrade backlog in the repo. Excluded from routine upgrade work.
