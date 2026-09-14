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

### `flux.rbac.thaum.xyz/role`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | `Namespace` |
| **Value** | A ClusterRole name; every app namespace carries `cluster-admin` |
| **Read by** | `generate-flux-reconciler` (Kyverno `GeneratingPolicy`) |
| **Effect** | Generates the `flux-reconciler` ServiceAccount there, a **RoleBinding** giving it that ClusterRole, and the `GitRepository` its Kustomizations read |

The value names the *rules*, not the reach. A RoleBinding confers only the
namespaced half of a ClusterRole and only inside its own namespace, so
`cluster-admin` here is namespace-admin in that namespace and nothing anywhere
else. The binding kind is the whole boundary, which is why the policy never
generates a ClusterRoleBinding: that would need the background controller to
hold `bind` on `cluster-admin`, after which any policy could mint it from a
label.

A namespace whose Kustomization applies something cluster-scoped — a
PersistentVolume, a chart's ClusterRole — cannot be served by a RoleBinding at
any width. It keeps this label and adds a hand-written ClusterRoleBinding on top,
in `k8s/namespaces/<app>/`; rights are additive, so dropping that binding narrows
the namespace back to confined rather than to nothing.

The `platform-<domain>` namespaces carry no label. Their `flux-reconciler` and
`GitRepository` are files, because they are on the bootstrap path — see
[how Flux is layered](../explanation/flux-layering.md). Only a cluster-admin can
set the label at all: Namespaces are cluster-scoped, and `edit` and `admin` get
get/list/watch on them and nothing more, so a tenant cannot label their way into
a wider reconciler.

Nothing may *run* as it. `validate-reconciler-sa-usage` denies any Pod that
names the ServiceAccount: impersonation mounts no token and the controllers'
own Pods run as themselves, so the only way a workload ends up with it is a
copy-pasted `serviceAccountName`, which would hand that workload the
reconciler's rights with no error and no symptom. That rule bounds workloads,
not people. `edit` carries `impersonate` on ServiceAccounts, so a tenant with
`edit` can act as the reconciler anyway, and one who controls the reconciled
git path can ship its token out. What bounds a tenant is the namespace edge — a
RoleBinding rather than a ClusterRoleBinding, `--no-cross-namespace-refs`, and
Pod Security Admission.

### `group.rbac.thaum.xyz/<group>`

| | |
| --- | --- |
| **Type** | Label, one per group |
| **Set on** | `Namespace` |
| **Value** | `edit` or `view`; `validate-group-labels` rejects anything else |
| **Read by** | `generate-group-rolebindings` (Kyverno `GeneratingPolicy`) |
| **Effect** | Generates a RoleBinding giving `oidc:k8s:group:<group>` that ClusterRole in that namespace |

The group is in the key and the tier in the value, so several groups can hold
different levels in one namespace. The `k8s:group:` prefix is derived and never
taken from the label: pocket-id groups are shared across every OIDC client, so a
bare group name could select an application's own SSO group. The group has to
exist in pocket-id with its members and be allowed for the kubectl client, or the
login fails before RBAC is consulted — see
[log in with kubectl](../how-to/log-in-with-kubectl.md).

`synchronize` is on: removing the label removes the binding, and an edit to the
binding is reverted. The ceiling is RBAC rather than the policy — the background
controller may `bind` only `edit` and `view`, so no label can produce a binding
to `admin` or `cluster-admin` whatever it asks for.

### `ingress.thaum.xyz/probe`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | `Ingress` |
| **Value** | `enabled` — the only value the selector matches |
| **Read by** | the `ingress` `Probe` (blackbox-exporter) |
| **Effect** | blackbox probes the host, and the app's `slo-probe-success.yaml` measures it |

Pairs with `ingress.thaum.xyz/probe-uri`; a label without the annotation probes
the bare host, which is rarely what you want.

Each probed app owns a Pyrra `ServiceLevelObjective` beside its Ingress,
`slo-probe-success.yaml`: availability as a person experiences it, end to end
through DNS, TLS and the ingress. Its indicator matches on the host rather
than the full probe URL, so changing `probe-uri` retunes the check without
emptying the SLO behind it. The target, and the measurement it was read from,
stay in the file because they differ per app.

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
pass.

There is no per-node opt-out to reach for instead: the DaemonSet carries no
`nodeSelector`, so every node reboots. Cordoning one does stop reboots, but
cluster-wide rather than for that node — a node unschedulable for 45 minutes
raises `NodeUnschedulable`, which is one of the alerts the gate blocks on.

Both readers are configured with this exact string, and neither fails loudly if
it stops matching: renaming the taint would leave the drain gate open and the
switchover late, with nothing to show for it. See
[how a node reboot is gated](../explanation/node-reboots.md).

## Upstream keys, local contract

Keys owned by other projects, where what they mean *here* is a local decision.

### `pod-security.kubernetes.io/enforce`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | `Namespace` |
| **Value** | `baseline` on every app namespace; `privileged` where the Namespace manifest says why |
| **Read by** | Pod Security Admission, built into the API server |
| **Effect** | A Pod that violates the tier is rejected when its controller creates it |

`baseline` is the tier that closes the route out of a namespace: it forbids
privileged containers, hostPath volumes and the host network, PID and IPC
namespaces, which together are how a pod reaches the node and, through the
node's credentials, the cluster. Without it a namespace role is bounded only by
RBAC, and RBAC does not describe what a container can reach once it is on a
host.

Not `restricted`, which also wants `runAsNonRoot`, a seccomp profile and every
capability dropped. Most images here would fail it, and enforcement failures
surface on the ReplicaSet rather than at apply, so a tier nothing meets stops
rollouts quietly.

`privileged` matches the cluster default and is set explicitly anyway, so that
the exemption is a reviewable line with a reason next to it rather than an
absence. `audit` and `warn` are left unset except in `platform-storage`, which
carries all three.

### `kustomize.toolkit.fluxcd.io/prune: disabled`

| | |
| --- | --- |
| **Type** | Annotation |
| **Set on** | every `Namespace`, every `PersistentVolume`, and the HelmReleases whose loss would take the cluster down |
| **Read by** | kustomize-controller |
| **Effect** | The object survives being dropped from its Kustomization's inventory |

Pruning is inventory-based: anything that drops an object from the inventory —
a rename, a file moved between directories, a restructure — deletes it. For a
Namespace that deletes everything inside it. For a PersistentVolume with
`Retain`, the data survives but the PVC bound to it does not, and recovery means
hand-clearing `claimRef` on a recreated PV while the app is down. Which
HelmReleases carry it, and why, is in
[how Flux is layered](../explanation/flux-layering.md#pruning-and-the-exceptions).

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

**Never on `unifi-nas`.** Those claims are subdirectories of a share the NAS
backs up itself, so restic would only copy the NAS onto the NAS;
[`validate-nfs-k8up-annotations`](admission-policies.md#validate-nfs-k8up-annotations)
warns on any `k8up.io/*` key that reaches one.

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

### `linbit.com/hostname`

| | |
| --- | --- |
| **Type** | Label |
| **Set on** | `Node` |
| **Value** | That node's own hostname |
| **Written by** | kubelet, from the topology keys the `linstor.csi.linbit.com` node plugin registers |
| **Effect** | Marks a node where a Piraeus volume can actually be attached |

Select it with `Exists` in a `nodeAffinity`, never as a `nodeSelector` — the
value differs per node, and a selector can only compare a key to one fixed
value. Use it for any Pod mounting a `piraeus-*` volume: the roaming classes put
no node affinity on the PV, so nothing else stops the scheduler picking a node
with no CSI plugin, where the Pod then waits forever on `CSINode <node> does not
contain driver linstor.csi.linbit.com`.

Prefer it over restating Piraeus's placement rule in the consumer, which
diverges silently the day that rule changes. Its one weakness is the mirror
image: kubelet writes topology labels at plugin registration and removes nothing
when a plugin stops, so a node that has *stopped* running Piraeus keeps the
label until something clears it.

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

It is also imported into LINSTOR as `Aux/topology/feature.node.kubernetes.io/module-signing-enforced`
by the `common` satellite configuration. Anything under `Aux/topology/` is
stripped of that prefix and reported by the driver as a CSI topology key, which
makes this label usable in a `piraeus-*` StorageClass's `allowRemoteVolumeAccess`
— see [storage classes](storage-classes.md). Two consequences worth knowing:
the key is only advertised at plugin *registration*, so a csi-node restart is
needed after the label first appears on a node; and a node without the label
gets no property, so the topology key is simply absent there.

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
