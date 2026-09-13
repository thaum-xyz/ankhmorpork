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
  ├── crds            the kinds every layer above it needs
  ├── namespaces      every namespace, plus what each platform domain needs first
  └── platform        the cluster's machinery, one Kustomization per domain
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
a directory its own tenant can change.

The `platform-<domain>` namespaces sit there too, for a third reason: each is
shared by several components, so keeping it in any one of their directories makes
that component's `prune` the whole domain's blast radius.

`platform-cluster` is the one whose directory there is also built by hand. It
holds the umbrellas, so it cannot be created by `namespaces` — that is one of
them — and `k8s/bootstrap/` applies the same directory before any Kustomization
exists. The other Namespace created outside `k8s/namespaces/` is `flux-system`,
by the component that still ships it, and it exists only until the apps move.

Each `platform-<domain>` is a directory rather than a file, because the Namespace
is not the only thing that has to be there first. A `Kustomization` reconciling
in that namespace reads a `GitRepository` in it — `--no-cross-namespace-refs`
allows nothing else — and applies as the `flux-reconciler` ServiceAccount there,
which `--default-service-account` resolves in the Kustomization's own namespace.
Neither can be created by the Kustomization that needs them, so both are
prerequisites of the domain rather than members of it.

**`platform`** is what a workload assumes is already there — CNI, storage drivers,
ingress controllers, cert-manager, admission control, the observability
collectors. Breaking something here breaks things that do not mention it.

**`apps`** is the workloads. An app can fail entirely without taking anything else
with it, which is the property the split exists to preserve.

`apps` `dependsOn` `platform`, so on a cold start nothing tries to claim a volume
before there is a CSI driver to answer.

## Why the Kustomizations live apart from the manifests

An app appears in two places: its manifests under `k8s/apps/<app>/`, and a Flux
`Kustomization` under `k8s/flux/apps/` that points at them.

The indirection looks redundant until you notice what the umbrella actually
applies: `path: ./k8s/flux/apps` — a **directory of Kustomizations**, not of
workloads. Adding an app means dropping one file into that directory; the
umbrella picks it up on its next reconcile and no existing file changes. It also
separates *how* a component is reconciled — its interval, its dependencies,
whether it prunes — from *what* the component is. Those change for different
reasons.

The platform is arranged the other way round, and the difference is deliberate.
A platform component has no Kustomization of its own; it is a directory named in
its domain's `k8s/platform/<domain>/kustomization.yaml`, and one Kustomization
reconciles the whole domain. The unit an app needs is isolation — one app failing
must not reach another. The unit the platform needs is a **namespace**: that is
what the reconciler identity, the group RoleBindings and a prune's blast radius
are all keyed to, and one Kustomization per namespace is what makes those the
same question rather than three that can drift apart.

Those domain Kustomizations do not live in `flux-system`. Each is in the
namespace it reconciles, reading the `GitRepository` there and applying as that
namespace's `flux-reconciler`. Nor do the umbrellas: they reconcile from
`platform-cluster`, which makes that namespace the seed the rest of the cluster
is built from, and leaves `flux-system` holding nothing but the app
Kustomizations and what they read.

## Ordering, where it genuinely matters

Only a handful of Kustomizations declare `dependsOn` — the
[reference page](../reference/flux-kustomizations.md) lists them — and two of those
are the umbrellas themselves. Everything else is order-independent by construction;
the exceptions are all cases where an object cannot be *accepted* by the API server
until something else exists:

| Object | Waits for | Why |
| --- | --- | --- |
| `platform` | `crds` | nearly everything ships a ServiceMonitor or PrometheusRule |
| `apps` | `platform`, `namespaces` | nothing claims a volume before there is a driver |
| `homer-services` | `homer` | it adds entries to a dashboard that must exist |
| HelmRelease `piraeus-operator` | HelmRelease `topolvm` | its storage pool *is* a topolvm thin pool |
| HelmRelease `cnpg-versity-gw` | HelmRelease `csi-nfs` | its claim is `unifi-nas`, and a policy rejects the PVC until the class exists |

The last two are between HelmReleases rather than Kustomizations because the
domains cannot depend on each other: `--no-cross-namespace-refs` lets a Flux
object name a `dependsOn` target only in its own namespace, and each domain is in
a different one. Ordering *between* domains has to come from the layer above
them, which is what `platform dependsOn crds` is.

One ordering constraint has no expression at all. `csi-nfs`, `piraeus-datastore`
and `cnpg-system` ship `policies.kyverno.io` objects whose CRDs come from the
kyverno chart in another domain, and the kyverno repository publishes no
CRD-only chart to hoist into `k8s/crds/`. On a cold bootstrap those objects fail
to apply and are retried each interval until kyverno installs; everything else in
the domain applies in the same pass, because Flux collects per-object errors
rather than abandoning the set.

`crds` is declared in `k8s/bootstrap/` and applies `k8s/crds/`, rather than being
a component of `platform`, precisely because `platform` depends on it — a layer
cannot depend on one of its own members. Its manifests sit outside `k8s/platform/`
for a second reason: everything under `k8s/platform/<domain>/` belongs to that
domain's Kustomization, and a directory there owned by another layer is a rule
with an exception.

`crds` and `kyverno` are the only two with `wait: true`, and
for the same reason: a dependency that is merely *applied* is not yet *usable*. A
CRD has to be established before an object of that kind will be accepted, and
admission control that is applied but not yet enforcing lets anything reconciled
into the gap slip past the policies unchecked.

## Pruning, and the exceptions

`prune: true` is the default here — nearly every Kustomization has it, which is what
makes deleting a directory delete the objects, and what makes the tutorial's
cleanup step work. The ones that opt out are listed on the
[reference page](../reference/flux-kustomizations.md), and they divide into two kinds.

**The umbrellas** (`platform`, `apps`, `crds`, `namespaces`)
do not prune because a transient failure to render one of them would otherwise be
read as "these components are gone" and cascade into deleting every component in
the layer. For `namespaces` the stake is higher still: deleting a Namespace takes
everything inside it, so removing one is deliberately two acts — drop the file,
then delete the object.

Everything else prunes, including all five platform domains — and including
Flux's own manifests, which `platform-cluster` reconciles like any other
component. What makes that survivable is not a `prune: false` but the two
mechanisms below, which is the same trade one level down: the guard sits on the
object that carries the risk rather than on a switch covering everything near
it. What used to be a
component-wide `prune: false` on the handful whose loss is unrecoverable —
cluster networking, the drivers behind every volume, the ingress path to
everything — is now `kustomize.toolkit.fluxcd.io/prune: disabled` on the
individual objects that carry the risk. Those are the `HelmRelease`s, because
pruning one *uninstalls* the release behind it, and each says what its own loss
would cost.

That is narrower in both directions. A component-wide switch also protected the
HelmRepository and values ConfigMap sitting beside the release — the orphans that
had to be cleared out by hand after the traefik and topolvm namespace moves — and
it protected them anonymously, leaving the next reader to infer from what the
component is why it was exempt.

All five also generate values ConfigMaps, which is one of the reasons those are
given stable names rather than hashed ones: with nothing pruning, a hashed name
would leave an orphan behind on every edit. See
[why Helm values live in a file](helm-values.md).

## What reconciliation actually costs

The `GitRepository` polls every 60 seconds, so a merge lands within a minute.
There is no webhook: a `Receiver` may only name resources in its own namespace,
so one in `flux-system` could never trigger the sources that belong to the other
namespaces.

The trap is that reconciling in the wrong order reports success while doing
nothing. `flux reconcile kustomization <name>` acts on whatever revision the
source currently holds — which, minutes after a merge, may still be the one before
it. The source has to be refreshed first:

```bash
flux reconcile source git ankhmorpork
flux -n flux-system reconcile kustomization <app>            # an app
flux -n platform-<domain> reconcile kustomization platform-<domain>
flux -n platform-cluster reconcile kustomization platform    # an umbrella
```

For a component whose values come from a `configMapGenerator`, there is a third
step, and it is not optional: a values edit changes the ConfigMap's contents but
not its name, so nothing in the HelmRelease spec moves and helm-controller has no
event to act on. [Why Helm values live in a file](helm-values.md) has the
mechanism and the trade; the step is:

```bash
flux -n <namespace> reconcile helmrelease <release>
```
