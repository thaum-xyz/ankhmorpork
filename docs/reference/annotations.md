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

### `thaum.xyz/kured-node-reboot`

| | |
| --- | --- |
| **Type** | Taint, effect `PreferNoSchedule` |
| **Set on** | `Node` |
| **Value** | None — presence is the signal |
| **Written by** | kured, when the node wants a reboot but another node holds the lock |
| **Read by** | the descheduler's `RemovePodsViolatingNodeTaints` plugin, and the CloudNativePG operator via `DRAIN_TAINTS` |
| **Effect** | The node stops attracting new Pods; movable Pods and Postgres primaries leave ahead of the drain |

**Output, not input.** kured adds it on its own and removes it when the reboot
finishes or the window closes; setting it by hand only lasts until kured's next
pass. To stop a node rebooting, relabel it `kured=disabled` instead — that
selector is what the DaemonSet schedules on.

Both readers are configured with this exact string, and neither fails loudly if
it stops matching: renaming the taint would leave the drain gate open and the
switchover late, with nothing to show for it. See
[how a node reboot is gated](../explanation/node-reboots.md).

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

### `feature.node.kubernetes.io/module-signing-enforced`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | `Node` |
| **Value** | `true`, `false`, `unknown` |
| **Written by** | the `module-signing-labeler` DaemonSet, via a `NodeFeature` object |
| **Effect** | None by itself — available to `nodeSelector`, `nodeAffinity` and `NodeFeatureRule` |

`true` means the kernel rejects unsigned out-of-tree modules, which is what
decides whether a node can run Piraeus: its DRBD module is built in a container
and signed by nobody. Node Feature Discovery has no source for this, so it is
fed to it — the DaemonSet reads sysfs and hands nfd-master a `NodeFeature`
object, the CRD NFD offers 3rd-party extensions. Manifest and reasoning:
[`k8s/platform/cluster/node-feature-discovery/module-signing/daemonset.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/cluster/node-feature-discovery/module-signing/daemonset.yaml).

Two companion labels carry the inputs the verdict was derived from, for when a
node classifies surprisingly:

| Label | Values |
| --- | --- |
| `feature.node.kubernetes.io/secureboot` | `enabled`, `disabled`, `legacy-bios`, `unknown` |
| `feature.node.kubernetes.io/kernel-lockdown` | `none`, `integrity`, `confidentiality`, `unavailable`, `unknown` |

!!! warning "Gate on the verdict, not on either input"

    Secure Boot is only the usual *cause* here. Lockdown can be raised from the
    kernel command line without it, and a kernel built without
    `CONFIG_LOCK_DOWN_IN_EFI_SECURE_BOOT` enforces nothing with Secure Boot on.
    The kernel rejects an unsigned module if the `sig_enforce` parameter is set
    **or** lockdown is above `none`, so the verdict ORs both paths.

    `feature.node.kubernetes.io/kernel-config.*` is not a substitute either. It
    describes what the running kernel was *built* to support and reads identically
    on every node here whatever the firmware is doing.

Exclude with `NotIn [true]` rather than selecting on `false`: a node whose label
is missing — labeler not run, discovery broken — then still matches, so a failure
of discovery cannot deschedule a storage workload that was running.

## Look load-bearing, are not

### `role: alert-rules` and `prometheus: k8s` on PrometheusRules

**Neither is required.** The `Prometheus` resource sets:

```yaml
ruleSelector: {}
ruleNamespaceSelector: {}
```

An empty selector matches everything, so **every** `PrometheusRule` in the
cluster is loaded regardless of its labels. Most rules that arrive inside charts
carry no `role` label at all and are loaded exactly the same.

They appear on hand-written rules because upstream examples carry them. Copying
them onto a new rule is harmless; omitting them is equally harmless. Nothing
breaks either way — which is worth knowing before someone spends an afternoon
wondering why a correctly-labelled rule is not firing.
