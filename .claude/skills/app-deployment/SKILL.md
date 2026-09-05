---
name: app-deployment
description: Deploy or extend an application in thaum-xyz/ankhmorpork — picking a StorageClass, satisfying the admission policies, wiring it into Flux, and rolling it out safely. Use when adding anything under k8s/apps/ or k8s/platform/, when adding or resizing persistent storage, when a PVC/Ingress/PDB is rejected or silently altered at admission, or when a reconcile reports success but nothing changed.
---

# Deploying an application

## Layout

An app is a directory of manifests plus a Flux Kustomization that points at it.

```
k8s/apps/<app>/          one Kubernetes object per file, type-based names
                         (deployment.yaml, pvc.yaml, namespace.yaml, pdb.yaml)
k8s/flux/apps/<app>.yaml Kustomization, namespace flux-system, path ./k8s/apps/<app>
```

Group distinct components into subdirectories with type-based names inside them
(`operator/release.yaml`, `gui/deployment.yaml`). Every app kustomization declares
its own `namespace:` — keep that, it is what stops objects landing in `default`.

Platform components live under `k8s/platform/` with their Kustomization in
`k8s/flux/platform/`.

## Choosing a StorageClass

Ask what the workload needs, in this order:

| Need | Class |
| --- | --- |
| Durable commit — Postgres, etcd, SQLite, anything transactional | `lvm-thin` or `piraeus-r2` |
| Survive losing a node | `piraeus-r2` |
| Lowest latency, restorable from backup | `lvm-thin` |
| Bulk sequential — media, backups, object storage | `unifi-nas` |
| Pod must move between nodes with its volume | `piraeus-r2-roaming` (≤32 GiB) |

**Never put anything transactional on `longhorn`.** Measured 2026-09-05: its
`fsync` completes 2–8× faster than the device it writes to, because the
controller-to-replica protocol has no flush operation at all. An acknowledged
commit sits in the drive's volatile cache. A pod kill, node reboot or kernel
panic is survivable; a power cut is not. It remains fine for workloads that can
lose recent writes, and it is the only class here offering snapshots and S3
backup.

Ceilings worth knowing before promising throughput:

- `lvm-thin` — indistinguishable from the bare device.
- `piraeus-r2` — reads at parity with `lvm-thin`; writes ~3 ms, ~12k IOPS,
  sequential write pinned at **111 MiB/s** by the replication link on every node.
- `longhorn` — sequential write pinned at **55 MiB/s** by its own engine, and the
  only class the page cache cannot accelerate at all.
- `unifi-nas` — **~100 MiB/s**, a single 1 GbE link. `nolock` means no byte-range
  locking, so nothing SQLite-backed belongs there.

Numbers and method: the storage guide artifact, and `bench/storage-2026-09/`
(local, untracked). Re-measure with `./full05.sh 4` after any hardware change —
and always keep a `hostpath-*` target per node, because it is the bare-device
reference that makes the durability audit possible.

## Admission policies you must satisfy

Kyverno runs these on every apply. The first four are the ones a new app trips.

- **`require-resource-requests`** — every container *and initContainer* sets both
  `cpu` and `memory` requests. Warn-only, so it will not block, but the omission
  is invisible until something is evicted.
- **`validate-ingress-contract`** — `spec.ingressClassName` must be `public`,
  `private` or `cloudflare`; the deprecated `kubernetes.io/ingress.class`
  annotation is rejected; public and private Ingresses must set TLS with an
  approved cert-manager ClusterIssuer and a `secretName` on every TLS entry.
- **`validate-pdb-drain-safety`** — PDBs must use `maxUnavailable`, never
  `minAvailable`, so the allowance follows replica count; it must permit at least
  one disruption; `unhealthyPodEvictionPolicy: AlwaysAllow`; and the selector must
  not be empty, because a policy/v1 empty selector matches every Pod in the
  namespace.
- **`validate-roaming-volume-size`** — PVCs on `piraeus-r2-roaming` are capped at
  **32 GiB** and denied above it. Use `piraeus-r2` for larger volumes.
- **`mutate-nfs-pvc-alert-exclusion`** — `unifi-nas` PVCs are labelled
  `excluded_from_alerts=true` automatically. Expected, not drift; do not remove it.

## Helm values

Values go in `values.yaml`, fed in through a `configMapGenerator` and
`valuesFrom` — never inline in `spec.values`. Renovate's `helm-values` manager
reads the file and cannot see inside a HelmRelease.

Set `generatorOptions.disableNameSuffixHash: true` and **name the generator
`values-<ReleaseName>`**, matching the release it feeds. This is settled
convention across every component here after past collisions; a bare `values`
collides as soon as a namespace gains a second release. A namespace with several
releases gets one per release — `values-postgres-sonarr`, `values-postgres-radarr`.
`valuesFrom.name` then references that literal name, with no hash suffix.

## Validate before pushing

```bash
make validate        # renders every kustomization against schemas + CRD catalog
make validate-flux   # asserts every live Flux Kustomization path exists
```

Both read **git-tracked** files, so a new manifest is invisible until staged —
`git add` first or a new app validates as though it does not exist.

For a HelmRelease, `kustomize build` does not render the chart. Use
`flux-build --api-versions monitoring.coreos.com/v1 <path>` for the full chain,
and fall back to `helm template` for releases whose values come from a runtime
Secret (pocket-id, cloudflared).

## Rolling out

Order matters, and getting it wrong reports success while changing nothing:

```bash
flux reconcile source git ankhmorpork
flux -n flux-system reconcile kustomization <component>   # regenerates the ConfigMap
flux -n <ns> reconcile helmrelease <release>              # now sees new values
```

`flux reconcile helmrelease --with-source` refreshes the *chart* source, not the
values ConfigMap. Run alone after a `values.yaml` change it logs "Helm upgrade
succeeded" having used the old values. Confirm the ConfigMap actually changed
before reconciling the release:

```bash
kubectl -n <ns> get cm values-<release> -o jsonpath='{.data.values\.yaml}' | grep <new-key>
```

The GitRepository can also still be on a pre-merge revision minutes after a merge,
so reconcile the source explicitly rather than assuming.

**The HelmRelease reconcile is not optional.** Because
`disableNameSuffixHash: true` gives the ConfigMap a stable name, a values change
alters its *content* but not `valuesFrom.name` — so nothing in the HelmRelease
spec changes and there is no event for helm-controller to act on. It notices via
`status.lastAttemptedConfigDigest` only on its next interval. Intervals here are
5m on 32 releases, 10m on one and **30m on fifteen**, so an unforced change can
sit for half an hour looking like a failed deploy. The hash suffix would trigger
it immediately, at the cost of a new ConfigMap name on every edit; stable names
are the deliberate trade, and reconciling the release is the price.

## Traps that have bitten

- **StorageClass fields are immutable.** `parameters`, `mountOptions`,
  `provisioner`, `reclaimPolicy`, `volumeBindingMode` cannot be patched; Helm
  fails. Back up the class, `kubectl delete sc <name>`, then reconcile
  Kustomization *then* HelmRelease so Helm recreates it. Bound PVs are unaffected —
  they carry their own copy — but **existing volumes keep the old settings**. NFS
  PVs can be patched in place (`/spec/mountOptions`) and take effect on remount;
  DRBD needs `linstor resource-definition drbd-options ... <pv>` per volume.
- **Never pin a Pod with `nodeName`.** It bypasses the scheduler, so nothing writes
  `volume.kubernetes.io/selected-node` on the PVC, the provisioner never fires, and
  any `WaitForFirstConsumer` class (`lvm-thin`, `piraeus-r2`) deadlocks Pending
  forever. Use `nodeAffinity`.
- **Helm deep-merges maps.** `{}` does not clear a chart default; only explicit
  `null` does.
- **A value at a path the chart does not read is silently inert.** Helm neither
  warns nor fails, so the values file reads as configuration while the app runs on
  defaults. Read intent off the *rendered* ConfigMap/Secret — `helm template` and
  diff against live — never off the values file. Expect this after every chart major.
- **Removing a field from git does not remove it from the object** when a previous
  manager holds server-side apply ownership and no longer applies it. Finish with
  `kubectl annotate <kind> <name> <key>-`; check with `--show-managed-fields=true`.
- **`kubectl get backup` resolves to `backups.longhorn.io`.** Always
  `backups.postgresql.cnpg.io`. Has produced false "no phase" readings twice.
- **A misdirected ServiceMonitor reports `down`, not missing.** Scraping a port
  serving an SPA returns 200 `text/html`, which Prometheus rejects while the app's
  own log shows a clean 200. Confirm via `/api/v1/targets` (`health`, `lastError`).
  Exporters on a separate listener need the port declared as a container port
  before a PodMonitor can select it by name.
- **Homebrew's `python3` lacks pyyaml here** — use `/usr/bin/python3`.

## After rollout

Confirm the HelmRelease is Ready and object `generation` is unchanged where you
expected no change — `generation == 1` is not the adoption test, they sit anywhere
from 1 to 26 across this fleet. Snapshot before, compare after.

For CloudNativePG specifically: never copy `install.remediation` from another
release. Its strategy is *uninstall*, which on an adopted Cluster deletes it and,
through `ownerReferences`, its PVCs.
