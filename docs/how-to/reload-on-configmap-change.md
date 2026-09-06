# Roll a workload when its ConfigMap changes { .quad-howto }

Mounting a ConfigMap as a volume does **not** restart the Pod. The kubelet syncs
the file within a minute or so, but a process that reads its configuration once
at startup never notices. Until it restarts, it runs configuration nobody can
tell is stale.

Opt a workload in and the `mutate-configmap-autoreload` Kyverno policy rolls it
whenever the ConfigMap changes.

## When you need this

Only when the process **cannot reload by itself**. Check first:

- Does it watch its own config file? Then do nothing.
- Does it expose a reload endpoint? Prefer a
  [`configmap-reload`](https://github.com/jimmidyson/configmap-reload) sidecar,
  as `blackbox-exporter` does — it reloads in place without dropping the Pod.
- Neither? Use this.

`pint` and `github-receiver` are both the third case: they read files at startup
and have no reload endpoint.

## Steps

Add one annotation to the **Deployment or StatefulSet's own metadata**, naming
the ConfigMap it reads:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    # The ConfigMap must be in the same namespace as the workload.
    autoreloader.thaum.xyz/configmap: pint-config
  name: pint
spec:
  template:
    metadata:
      # The policy writes autoreloader.thaum.xyz/version in here.
```

That is the whole change. On every apply the policy reads that ConfigMap's
`resourceVersion` and stamps it into `spec.template.metadata.annotations`, so a
changed ConfigMap changes the Pod template, and a changed Pod template rolls the
Pods.

!!! danger "It goes on the workload, not the Pod template"

    The policy matches `object.metadata.annotations` and *writes into*
    `spec.template.metadata.annotations`. Putting the opt-in in the Pod template
    means the policy never matches — and it fails **silently**, because
    `failurePolicy: Ignore` means an unmatched or erroring policy just skips.
    This has already happened once, in
    [#1300](https://github.com/thaum-xyz/ankhmorpork/pull/1300).

## Verify it

Before merging, ask the API server what the webhook would produce:

```bash
kubectl -n <namespace> apply --server-side \
  --field-manager=kustomize-controller --dry-run=server \
  -o jsonpath='{.spec.template.metadata.annotations}' \
  -f path/to/deployment.yaml
```

You want an `autoreloader.thaum.xyz/version` that matches the live ConfigMap:

```bash
kubectl -n <namespace> get cm <name> -o jsonpath='{.metadata.resourceVersion}'
```

If the version annotation is missing, the policy did not match — check the
annotation is on the workload's metadata and that the ConfigMap name is right.

After merging, the same two values should agree on the live object:

```bash
kubectl -n <namespace> get deploy <name> \
  -o jsonpath='{.spec.template.metadata.annotations}'
```

## Expect two reconciles, not one

Flux applies the workload **before** it writes the updated ConfigMap, so the
first reconcile stamps the version that is still current at that moment and
nothing changes. The next one picks up the new value and rolls the Pods.

With a 5m Kustomization interval that is **up to ten minutes** between merging a
ConfigMap change and seeing new Pods. Measured on a real change:

```
configmap written by kustomize-controller   05:50:41
deployment written by kustomize-controller  05:43:34   <- skipped this reconcile
pod rolled                                  05:57
```

To skip the wait, reconcile explicitly:

```bash
flux reconcile source git ankhmorpork
# Twice: the first pass stamps the pre-update version, the second picks up the new one.
flux -n flux-system reconcile kustomization <component>
flux -n flux-system reconcile kustomization <component>
```

## Limits

- **ConfigMaps only.** Secrets would need the Kyverno admission controller to
  hold read on every Secret in the cluster; it currently has none. See
  [the explanation](../explanation/configmap-autoreload.md#why-not-secrets).
- **One ConfigMap per workload.** The annotation takes a single name.
- **Deployments and StatefulSets only.** DaemonSets are not matched.
- **A missing ConfigMap is silent.** `failurePolicy: Ignore` means a typo in the
  name skips the stamp rather than blocking the apply — deliberately, so a
  renamed ConfigMap cannot stop deploys.
