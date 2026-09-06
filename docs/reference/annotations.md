# Annotations and labels { .quad-reference }

Keys this cluster gives meaning to, beyond the [well-known Kubernetes
ones](https://kubernetes.io/docs/reference/labels-annotations-taints/).

Three groups: keys defined here, upstream keys whose *contract* is local, and
keys that look load-bearing but are not.

## Defined here

Under `thaum.xyz`, so they cannot collide with anything upstream.

### `autoreloader.thaum.xyz/configmap`

| | |
| --- | --- |
| **Type** | Annotation |
| **Set on** | `Deployment`, `StatefulSet` — the object's **own** `metadata`, not the Pod template |
| **Value** | Name of a ConfigMap in the same namespace |
| **Read by** | `mutate-configmap-autoreload` (Kyverno `MutatingPolicy`) |
| **Effect** | The workload's Pods roll when that ConfigMap changes |

For a process that reads its configuration once at startup. See
[the how-to](../how-to/reload-on-configmap-change.md) and
[the reasoning](../explanation/configmap-autoreload.md).

!!! danger "On the workload, not the Pod template"

    The policy matches `object.metadata.annotations`. An opt-in placed in
    `spec.template.metadata.annotations` never matches, and because the policy is
    `failurePolicy: Ignore` it produces no stamp, no error and no rollout.

### `autoreloader.thaum.xyz/version`

| | |
| --- | --- |
| **Type** | Annotation |
| **Set on** | `spec.template.metadata` of an opted-in workload |
| **Value** | The `resourceVersion` of the named ConfigMap |
| **Written by** | `mutate-configmap-autoreload`, on every apply |

**Output, not input.** Never set it by hand — it is the mechanism, and a manual
value is overwritten on the next apply. Its presence is how you confirm the
policy matched.

### `ingress.thaum.xyz/probe`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | `Ingress` |
| **Value** | `enabled` — the only value the selector matches |
| **Read by** | the `ingress` `Probe` (blackbox-exporter) |
| **Effect** | blackbox probes the host, and the target joins `blackbox-probe-success` |

Pairs with `ingress.thaum.xyz/probe-uri`; a label without the annotation probes
the bare host, which is rarely what you want.

!!! warning "On the Ingress that declares TLS"

    blackbox derives the scheme from whether the Ingress declares `spec.tls`. On a
    host with both a traefik and a cloudflare Ingress, labelling the cloudflare one
    builds an `http://` target the tunnel never answers. Label the one with TLS.

Charts that expose `ingress.annotations` but no `ingress.labels` need this
patched on through `postRenderers` — see pocket-id and atuin.

### `ingress.thaum.xyz/probe-uri`

| | |
| --- | --- |
| **Type** | Annotation |
| **Set on** | `Ingress`, alongside the label above |
| **Value** | A path, e.g. `/api/health` |
| **Read by** | the `ingress` `Probe`, as `__meta_kubernetes_ingress_annotation_ingress_thaum_xyz_probe_uri` |
| **Effect** | Appended to `scheme://host` to form the probe target |

**Probe an endpoint the application serves, not its front door.** The
`http_2xx` module follows redirects and asserts nothing about the body, so `/`
on an SPA returns 200 from static assets with the backend dead — and on a host
behind an oauth2 proxy it can return 200 from the *identity provider's* login
page, which is how the `pdf` probe stayed green while measuring pocket-id.

Prefer what the app's own readiness probe uses. Good examples in tree:
`/api/health` (karakeep, grafana — the latter also reports database status),
`/api/v1/status` (seerr), `/healthz` (atuin), `/actuator/health` (stirling-pdf),
`/.well-known/openid-configuration` (pocket-id).

Omitting the annotation is not a way to opt out — the relabeling then builds the
bare host, silently. Remove the label instead.

## Upstream keys, local contract

Keys owned by other projects, where what they mean *here* is a local decision.

### `k8up.io/backup`

| | |
| --- | --- |
| **Type** | Annotation |
| **Set on** | `PersistentVolumeClaim` |
| **Value** | `"true"` |
| **Effect** | Includes the claim in K8up backups |

**Opt-in, not opt-out.** K8up runs with `skipWithoutAnnotation: true`, so an
unannotated claim in a namespace with a `Schedule` is *not* backed up. Without
that setting, every bound claim would be enrolled — including the multi-terabyte
media volumes, onto the NAS they already live on.

Related, same object: `k8up.io/backupcommand` for an application-consistent dump
instead of a file copy, and `k8up.io/backup-restic-args` for per-claim excludes.

### `excluded_from_alerts`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | `PersistentVolumeClaim` |
| **Value** | `"true"` |
| **Read by** | `KubePersistentVolumeFillingUp` and its Inodes and critical variants |
| **Effect** | Suppresses fill-level alerts for that claim |

Applied automatically to `unifi-nas` claims by the `mutate-nfs-pvc-alert-exclusion`
Kyverno policy — that driver puts every claim in a subdirectory of one share, so
all of them report the share's fill level as their own. Also set by hand on
claims where the number is real but uninteresting.

Reaches Prometheus only because `persistentvolumeclaims=[excluded_from_alerts]`
is in kube-state-metrics' `metricLabelsAllowlist`; KSM emits no `kube_*_labels`
series for anything not listed there.

### `prometheus-name`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | ConfigMaps generated by prometheus-operator |
| **Value** | The `Prometheus` resource's name — `k8s` here |
| **Read by** | pint's `k8s-sidecar` container |

Set by the operator, not by hand. pint selects on it to mirror every rule file
Prometheus has actually loaded, which is why pint lints the live rule set rather
than what happens to be in git.

### `grafana_folder`

| | |
| --- | --- |
| **Type** | Annotation |
| **Set on** | Dashboard ConfigMaps |
| **Read by** | Grafana's dashboard sidecar |
| **Effect** | Files the dashboard under that folder |

## Look load-bearing, are not

### `role: alert-rules` and `prometheus: k8s` on PrometheusRules

**Neither is required.** The `Prometheus` resource sets:

```yaml
ruleSelector: {}
ruleNamespaceSelector: {}
```

An empty selector matches everything, so **every** `PrometheusRule` in the
cluster is loaded regardless of its labels. 58 of them carry no `role` label at
all and are loaded exactly the same.

They appear on hand-written rules because upstream examples carry them. Copying
them onto a new rule is harmless; omitting them is equally harmless. Nothing
breaks either way — which is worth knowing before someone spends an afternoon
wondering why a correctly-labelled rule is not firing.
