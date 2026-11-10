# FluxCDReconciliationFailure { .quad-howto }

## Meaning

A Flux `Kustomization`, `HelmRelease` or source has had `Ready` at `False` or
`Unknown` for 15 minutes. The alert's `customresource_kind`, `namespace` and
`name` labels identify it. A suspended object never fires this.

## Impact

Merges to `master` stop reaching whatever the object delivers. What is already
running keeps running, on the last version that applied.

| Object | What stops |
| --- | --- |
| `Kustomization` | every object in its path, not only the failing one — a pass [stops at its first error](../../explanation/flux-layering.md#ordering-where-it-genuinely-matters). For a `platform-<domain>` that is the whole domain. |
| `HelmRelease` | upgrades and values changes; the release stays on the revision last deployed |
| `GitRepository`, `HelmRepository`, `OCIRepository` | everything that reads from it, which keeps using the last artifact fetched |

The cost grows with time: every merge since the failure queues behind it, and
the whole queue lands in one pass when it clears.

## Diagnosis

1. Read why Flux says the object is not ready. The `Ready` condition's message
   is the error from the last attempt and names the object that failed. For a
   `HelmRelease`, `History` in the same output shows which chart version is
   deployed and since when.

    ```bash
    kubectl -n <namespace> describe <customresource_kind> <name>
    ```

2. For a `Kustomization`, list what has merged since it last applied.
   `Last Applied Revision`, `Last Attempted Revision` and `Path` are in the
   output of step 1. The oldest commit that touches the failing object is
   usually the cause; the rest is what lands when it clears.

    ```bash
    git log --oneline <applied-sha>..<attempted-sha> -- <path>
    ```

3. If the message is cut short, read the controller's own log. Use
   `helm-controller` for a `HelmRelease` and `source-controller` for a source.

    ```bash
    kubectl -n platform-cluster logs deploy/kustomize-controller --since=30m | grep <name>
    ```

4. Match the message against the table below.

## Mitigation

| The message says | Cause | Fix |
| --- | --- | --- |
| `dry-run failed (Invalid)` … `field is immutable` | A manifest changed a field Kubernetes cannot update in place. Seen here on a `Job` whose image Renovate had bumped ([#1638](https://github.com/thaum-xyz/ankhmorpork/issues/1638)). | For a finished `Job`, delete it and the next pass recreates it from git. For anything that holds data — a PVC, a StatefulSet, a StorageClass — the change itself is wrong: revert it. |
| `Helm upgrade failed` … `execution error at` | The new chart version does not render with the values in git, typically after a chart major ([#1535](https://github.com/thaum-xyz/ankhmorpork/issues/1535)). | Change `values.yaml` to what the message asks for, or pin the previous chart version in `release.yaml`. The deployed release is untouched meanwhile. |
| `Helm upgrade failed` … `context deadline exceeded` | The chart applied and its workloads did not become ready within the release's `timeout`. | The workload is the problem, not Flux: start from `kubectl -n <namespace> get pods`. For a database release, see [what it waits for](../../explanation/helm-release-waiting.md). |
| `dry-run failed` … `no matches for kind` | The CRD for that kind is not established. | On a rebuild it clears on a later retry. If it persists, the release that ships the CRD is failing — repeat the diagnosis on that one. |
| `admission webhook` … `denied the request` | A Kyverno policy rejected the object; the message quotes the rule. | Fix the manifest. Every policy and what it requires is in [admission policies](../../reference/admission-policies.md). |
| `is forbidden: User "system:serviceaccount:<namespace>:flux-reconciler"` | The namespace's own reconciler tried to apply something cluster-scoped or in another namespace. | Move the object to `k8s/namespaces/<app>/` — [why that directory exists](../../explanation/flux-layering.md#why-the-kustomizations-live-apart-from-the-manifests). |
| `dependency '<namespace>/<name>' is not ready` | The object waits for another Flux object. | Repeat the diagnosis on the one it names. |
| `failed to checkout`, `failed to fetch` on a source | GitHub or a chart registry was unreachable, or refused the request. | Usually transient; retry. If it persists and the remote is up, the fault is the cluster's DNS or egress. |
| *several objects across namespaces at once* | Not Flux. Releases time out while their Pods cannot schedule — a node being drained, or down ([#1374](https://github.com/thaum-xyz/ankhmorpork/issues/1374)). | Look at the nodes first; these clear when the cluster does. |

The fix is nearly always a merge, and Flux retries on the object's own interval.
To retry at once, reconcile it [in its own namespace](../../explanation/flux-layering.md#what-reconciliation-actually-costs):

```bash
flux -n <namespace> reconcile kustomization <name> --with-source
```

A `HelmRelease` whose `Stalled` condition reads `RetriesExceeded` has stopped
trying. A change to its chart or values restarts it without help; when the fix
was somewhere else, restart it by hand:

```bash
flux -n <namespace> reconcile helmrelease <name> --reset
```

The alert resolves when the object reports `Ready`:

```bash
kubectl -n <namespace> get <customresource_kind> <name>
```

If the failure is expected while you work on the object,
[silence it](../silence-alerts-for-maintenance.md) for the duration rather than
suspending the object — a suspended object stops alerting and is easy to forget.
