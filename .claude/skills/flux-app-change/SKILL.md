---
name: flux-app-change
description: Change an app in thaum-xyz/ankhmorpork and prove it safe — kustomizeconfig removal, chart/image upgrades, or any edit that alters what Flux applies. Use when editing anything under apps/, base/ or core/, or when converting an app off kustomizeconfig.yaml.
---

# Changing a Flux-managed app

## Prove the render before touching the cluster

1. Capture the baseline **before editing**: `kustomize build <parent> > before.yaml`.
2. Edit, then `kustomize build <parent> > after.yaml`.
3. Compare object *sets* keyed on `(apiVersion, kind, namespace, name)`, then full
   specs. Anything unintended is a real change to a running workload.

For anything involving a HelmRelease, `kustomize build` is not enough — it does
not render the chart. Use `flux-build --api-versions monitoring.coreos.com/v1 <path>`
for the full chain. It cannot resolve releases whose values come from a runtime
Secret (pocket-id, cloudflared); fall back to `helm template` against the chart.

## Traps that have actually bitten

- **Build the parent, never the subdirectory.** The namespace is injected by the
  parent, so building a subdir yields namespace-less objects and `kubectl diff`
  compares them against `default` — reporting every object as new.
- **Three apps have no `namespace:` on their parent kustomization**: pocket-id,
  paperless, multimedia. Their manifests each carried their own. A new bundle that
  forgets to declare one silently targets `default`. Assert the namespace of every
  emitted object.
- **Removing a field from git does not remove it from the object.** If a previous
  manager (usually kustomize-controller) holds server-side apply ownership of that
  field and no longer applies the object, its claim is a fossil that never expires.
  Finish with `kubectl annotate <kind> <name> <key>-`. Check with
  `kubectl get ... -o json --show-managed-fields=true`.
- **`kubectl get backup` resolves to `backups.longhorn.io`.** Always
  `backups.postgresql.cnpg.io`. This has produced false "no phase" readings twice.
- **`generation` unchanged is the adoption test, not `generation == 1`.** Across
  this fleet they sit anywhere from 1 to 26. Snapshot before, compare after.
- **Helm deep-merges maps.** `{}` in a values file does not clear a chart default;
  only an explicit `null` does.
- Homebrew's `python3` lacks pyyaml here — use `/usr/bin/python3`.

## Removing a kustomizeconfig.yaml

32 of these exist. Each does one thing: a `nameReference` rewriting
`spec.valuesFrom[].name` on a HelmRelease so it tracks a hashed ConfigMap name.

Replace it with a stable name instead:

1. Add `generatorOptions.disableNameSuffixHash: true` to the kustomization
   (or per-generator `options:` when the file has more than one generator —
   photos needs this, or immich's release is upgraded for nothing).
2. Drop `configurations: [kustomizeconfig.yaml]` and delete the file.
3. `valuesFrom.name` becomes the literal generator name. Names must be unique per
   namespace: most apps generate `values`, so name others distinctly
   (`postgres-values`).
4. Verify the render: the only diff should be the ConfigMap losing its hash suffix
   and the HelmRelease reference following it.

The ConfigMap name change makes helm-controller re-render, so expect one release
revision per app. It detects value changes via `status.lastAttemptedConfigDigest`,
so the hash was never needed for change detection.

## After merge

`flux reconcile kustomization <app> -n flux-apps --with-source`, then confirm the
HelmRelease is Ready and object generations are unchanged. Roughly 21 components
are suspended by design — check `spec.suspend` before wondering why nothing moved.
