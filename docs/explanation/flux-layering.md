# How Flux is layered { .quad-explanation }

Nothing reaches this cluster except by being merged to `master`. There is no
`kubectl apply` step, and no way to install something by hand that survives the
next reconcile. What that costs is a structure that has to encode ordering,
blast radius and failure isolation in configuration, because there is no operator
present to sequence anything.

That structure is three layers deep, and the shape is not arbitrary.

## The three layers

```
k8s/bootstrap/        applied once by hand: the GitRepository and the umbrellas
  ├── namespaces      the namespaces apps are deployed into
  └── platform        the cluster's machinery
        └── apps      the workloads
```

The current membership of each layer, with every interval, prune and wait
setting, is in [Flux Kustomizations](../reference/flux-kustomizations.md).

**`k8s/bootstrap/`** is the seed: a `GitRepository` pointing at this repo, and
the umbrella `Kustomization`s. It is the only thing ever applied manually, and
it exists solely so that everything after it can be applied by Flux — which
also means a change to a file in it does nothing until someone runs
`kubectl apply -k k8s/bootstrap`.

One of its umbrellas, `namespaces`, creates the namespace every app is deployed
into, from `k8s/namespaces/`. They sit here rather than with the app for two
reasons: a Namespace is cluster-scoped, so an app reconciling under a
namespace-scoped ServiceAccount could not apply its own; and a namespace's
`group.rbac.thaum.xyz/<group>` labels are an access grant, which must not live in
a directory its own tenant can change. Platform namespaces stay with their
components, which are applied by a cluster-admin identity anyway.

**`platform`** is what a workload assumes is already there — CNI, storage drivers,
ingress controllers, cert-manager, admission control, the observability
collectors. Breaking something here breaks things that do not mention it.

**`apps`** is the workloads. An app can fail entirely without taking anything else
with it, which is the property the split exists to preserve.

`apps` `dependsOn` `platform`, so on a cold start nothing tries to claim a volume
before there is a CSI driver to answer.

## Why the Kustomizations live apart from the manifests

Each component appears in two places: its manifests under `k8s/platform/…` or
`k8s/apps/…`, and a Flux `Kustomization` under `k8s/flux/platform/` or
`k8s/flux/apps/` that points at them.

The indirection looks redundant until you notice what the umbrella
Kustomizations actually apply: `path: ./k8s/flux/apps` — a **directory of
Kustomizations**, not of workloads. Adding an app means dropping one file into
that directory; the umbrella picks it up on its next reconcile and no existing
file changes.

It also means the thing that decides *how* a component is reconciled — its
interval, its dependencies, whether it prunes — is separate from *what* the
component is. Those change for different reasons.

## Ordering, where it genuinely matters

Only a handful of Kustomizations declare `dependsOn` — the
[reference page](../reference/flux-kustomizations.md) lists them — and two of those
are the umbrellas themselves. Everything else is order-independent by construction;
the exceptions are all cases where an object cannot be *accepted* by the API server
until something else exists:

| Component | Waits for | Why |
| --- | --- | --- |
| `platform` | `prometheus-operator-crds` | nearly everything ships a ServiceMonitor or PrometheusRule |
| `kyverno-policies`, `cnpg-system`, `csi-nfs` | `kyverno` | policies need their CRDs; the others are validated by them |
| `piraeus-datastore` | `topolvm`, `kyverno` | its storage pool *is* a topolvm thin pool |
| `homer-services` | `homer` | it adds entries to a dashboard that must exist |

`prometheus-operator-crds` sits in `k8s/bootstrap/` rather than in `platform`
precisely because `platform` depends on it — a layer cannot depend on one of its
own members.

`prometheus-operator-crds` and `kyverno` are the only two with `wait: true`, and
for the same reason: a dependency that is merely *applied* is not yet *usable*. A
CRD has to be established before an object of that kind will be accepted, and
admission control that is applied but not yet enforcing lets anything reconciled
into the gap slip past the policies unchecked.

## Pruning, and the exceptions

`prune: true` is the default here — nearly every Kustomization has it, which is what
makes deleting a directory delete the objects, and what makes the tutorial's
cleanup step work. The ones that opt out are listed on the
[reference page](../reference/flux-kustomizations.md), and they divide into two kinds.

**The umbrellas** (`platform`, `apps`, `prometheus-operator-crds`, `namespaces`)
do not prune because a transient failure to render one of them would otherwise be
read as "these components are gone" and cascade into deleting every component in
the layer. For `namespaces` the stake is higher still: deleting a Namespace takes
everything inside it, so removing one is deliberately two acts — drop the file,
then delete the object.

**Five platform components** — `cilium`, `flux-system`, `topolvm`,
`piraeus-datastore`, `traefik` — do not prune because pruning them destroys
something unrecoverable: cluster networking, Flux itself, the PVs holding every
volume, or the ingress path to everything.

Only `flux-system` records the reason in a comment. The other four share an
obvious property, but that is inference from what they are, not something the
repository states — worth knowing before assuming any of them can safely be
switched back.

All five also generate values ConfigMaps, which is one of the reasons those are
given stable names rather than hashed ones: with nothing pruning, a hashed name
would leave an orphan behind on every edit. See
[why Helm values live in a file](helm-values.md).

## What reconciliation actually costs

The `GitRepository` polls every 60 seconds, and a GitHub webhook `Receiver`
triggers it on push, so a merge normally lands in seconds rather than a minute.

The trap is that reconciling in the wrong order reports success while doing
nothing. `flux reconcile kustomization <name>` acts on whatever revision the
source currently holds — which, minutes after a merge, may still be the one before
it. The source has to be refreshed first:

```bash
flux reconcile source git ankhmorpork
flux -n flux-system reconcile kustomization <component>
```

For a component whose values come from a `configMapGenerator`, there is a third
step, and it is not optional: a values edit changes the ConfigMap's contents but
not its name, so nothing in the HelmRelease spec moves and helm-controller has no
event to act on. [Why Helm values live in a file](helm-values.md) has the
mechanism and the trade; the step is:

```bash
flux -n <namespace> reconcile helmrelease <release>
```
