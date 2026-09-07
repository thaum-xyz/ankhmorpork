---
name: app-deployment
description: Deploy, extend or restructure an application in thaum-xyz/ankhmorpork — picking a StorageClass, satisfying the admission policies, wiring it into Flux, and rolling it out safely. Use when adding anything under k8s/apps/ or k8s/platform/, when adding or resizing persistent storage, when replacing a Helm release with plain manifests or otherwise removing a HelmRelease, when a PVC/Ingress/PDB is rejected or silently altered at admission, or when a reconcile reports success but nothing changed.
---

# Deploying an application

Cluster documentation lives in `docs/` and is published at
<https://docs.thaum.xyz>. This skill covers what an agent needs while making the
change; it points at those pages rather than restating their tables, so when the
two disagree the docs are right.

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

Worked end-to-end example, including the reconcile and the cleanup:
`docs/tutorial/index.md`.

## Choosing a StorageClass

Full decision procedure: `docs/how-to/choose-a-storage-class.md`. Capabilities,
constraints and measured ceilings: `docs/reference/storage-classes.md`. Read those
rather than reproducing their tables here.

The short version, in the order the questions matter:

1. Needs real RWX → `unifi-nas`, the only RWX class. Check the RWX is real first:
   a single-replica Deployment often needs it only because a RollingUpdate briefly
   runs two Pods, and `strategy: Recreate` removes that.
2. Transactional → not `unifi-nas` (`nolock`, no byte-range locking).
3. App replicates itself (the CNPG clusters do) → `lvm-thin`.
4. Bulk sequential → `unifi-nas`.
5. A config volume of plain files the app rewrites rarely → `unifi-nas`, for
   scheduling freedom rather than speed: `csi-nfs` runs on all four nodes,
   linstor on three. Not when a UI reads it a file at a time (sonarr's and
   radarr's MediaCover), and not when it would be the app's only reason to
   depend on the NAS — prowlarr dropped its claim instead.
6. **Everything else → `piraeus-r2-roaming`.** This is the default for application
   data and the most used class here. Same performance as `piraeus-r2`; the only
   difference is that a Pod landing where no replica exists runs over the network
   until LINSTOR replicates to it.
7. Over 32 GiB, or cannot tolerate that window → `piraeus-r2`.

`lvm-thin` pins the Pod to one node, so kured means downtime on every reboot of
that node. Use it only where the app provides its own redundancy.

Why the classes differ, and how a durability claim was tested rather than trusted:
`docs/explanation/storage-durability.md`.

## Admission policies you must satisfy

`docs/reference/admission-policies.md` is **generated from the policies
themselves** and is authoritative — read it rather than a copy. Five policies,
of which `validate-ingress-contract`, `validate-helm-chart-version` and
`validate-roaming-volume-size` **deny**.

Two that mislead if you only read the names:

- **`require-resource-requests` is warn-only.** It will not block, so a missing
  request is invisible until something is evicted. Set them anyway, on
  initContainers too.
- **`mutate-nfs-pvc-alert-exclusion`** labels `unifi-nas` PVCs
  `excluded_from_alerts=true` automatically. Expected, not drift; do not remove it.

For ingress specifically: `docs/how-to/expose-an-app.md`.

## Helm values

Values go in `values.yaml`, fed through a `configMapGenerator` and `valuesFrom` —
never inline in `spec.values`, because Renovate's `helm-values` manager cannot see
inside a HelmRelease. Set `disableNameSuffixHash: true` and name the generator
`values-<ReleaseName>`, matching the release it feeds.

Why, and what the stable name costs: `docs/explanation/helm-values.md`.

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

- The GitRepository can still be on a pre-merge revision minutes after a merge, so
  reconcile the source explicitly rather than assuming.
- `flux reconcile helmrelease --with-source` refreshes the *chart* source, not the
  values ConfigMap. Run alone after a `values.yaml` change it logs "Helm upgrade
  succeeded" having used the old values.
- **The HelmRelease reconcile is not optional** — a values change moves no field in
  the HelmRelease spec, so there is no event for helm-controller to act on.
- Keep `spec.interval` at 5m on every HelmRelease. `spec.chart.spec.interval` is a
  different knob and can stay high.

Confirm the ConfigMap actually changed before reconciling the release:

```bash
kubectl -n <ns> get cm values-<release> -o jsonpath='{.data.values\.yaml}' | grep <new-key>
```

Full reasoning: `docs/explanation/flux-layering.md` and
`docs/explanation/helm-values.md`.

## Replacing a Helm release with plain manifests

Worth doing when the chart has stopped paying for itself — it ships a handful of
objects and most of them need `postRenderers` patches to be usable. atuin was
five objects, three patched, so the chart was pure indirection.

**Do it in two commits, and not in one.** Removing the HelmRelease makes
helm-controller *uninstall* the release, and Helm deletes by name from its stored
manifest — the same names the new plain manifests use. kustomize-controller
applies the new objects and deletes the HelmRelease in the same reconcile, then
the uninstall lands afterwards and deletes what was just applied. The
Kustomization is left `Ready=True` over a namespace with nothing in it.

The guard is `helm.sh/resource-policy: keep`, which makes Helm leave a resource
alone on uninstall. It has to reach the objects **through the chart**:

```yaml
# commit 1 — via postRenderers, or ingress.annotations etc. where the chart has them
- target: {kind: Deployment, name: <app>}
  patch: |-
    - op: add
      path: /metadata/annotations/helm.sh~1resource-policy
      value: keep
```

Merge that, confirm the annotation is live on every object the chart owns, and
only then commit the plain manifests and drop the HelmRelease. Helm skips the
annotated objects, kustomize adopts them in place, and nothing restarts.

**Annotating the live objects with `kubectl annotate` instead does not work.**
kustomize-controller applies with server-side apply and force; it takes ownership
of `metadata.annotations`, the new manifests do not carry the annotation, and the
apply strips it moments before the uninstall reads it. This cost a ~4 minute
atuin outage on 2026-09-06.

Carry across exactly:

- **`spec.selector` on a Deployment is immutable** — copy it from the live object
  and diff it, or the apply fails and the only fix is delete-and-recreate.
- **The full env set.** Diff it rather than eyeballing:
  `kubectl get deploy <app> -o jsonpath='{..env[*].name}'` against the manifest.
  Empty-valued vars the chart set are still part of the contract; drop them in a
  later commit once the app is known not to distinguish unset from empty.

Recovery, if the objects do get deleted: `flux -n flux-system reconcile
kustomization <name>` recreates them, and is safe once the HelmRelease is gone
because nothing is left to uninstall. There is no `--force` flag on that command.

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
  any `WaitForFirstConsumer` class (`lvm-thin`, both piraeus classes) deadlocks Pending
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
  The mirror image also bites: **applying a manifest that omits a field strips it**
  once kustomize-controller force-owns the parent map, which is why an annotation
  added out of band with `kubectl annotate` does not survive the next reconcile.
- **A green Kustomization is not evidence the objects exist.** `Ready=True` means
  the apply succeeded, not that nothing deleted the result afterwards — a Helm
  uninstall or another controller can remove objects out of band and the status
  never moves. Check the objects.
- **`kubectl get backup` is ambiguous.** It resolves to `backups.k8up.io` since
  k8up was installed — it was `backups.longhorn.io` before that. Always spell out
  `backups.postgresql.cnpg.io` or `backups.k8up.io`. Has produced false "no phase"
  readings twice.
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
