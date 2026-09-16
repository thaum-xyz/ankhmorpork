# Why Helm values live in a file { .quad-explanation }

Every HelmRelease here that sets values at all — all but
`prometheus-operator-crds`, which takes the chart's defaults — feeds them in from a
ConfigMap rather than writing them inline. The *Values from* column in
[Helm releases](../reference/helm-releases.md) is the check:

```yaml
# kustomization.yaml
configMapGenerator:
  - name: values-myapp
    files:
      - values.yaml=values.yaml
```

```yaml
# release.yaml
spec:
  valuesFrom:
    - kind: ConfigMap
      name: values-myapp
```

The generated ConfigMap carries a content hash — `values-myapp-7f9c2b4h8d` — and
the `valuesFrom` entry above is rewritten to match. That rewrite is not
automatic: it comes from a component every Flux Kustomization root pulls in.

```yaml
# the root's kustomization.yaml
components:
  - ../../kustomize/helmrelease-values
```

Inline `spec.values` would be shorter and one file fewer. There are no releases
using it, and the reason is not tidiness.

## Renovate cannot see inside a HelmRelease

Renovate's `helm-values` manager reads `values.yaml`. It has no manager that looks
inside a HelmRelease's `spec.values`, so anything written there is invisible to it.

That matters more than it first appears, because a chart's values are full of
things that need updating and are not the chart version:

```yaml
# k8s/platform/network/cloudflared/values.yaml
cloudflared:
  image:
    repository: ghcr.io/strrl/cloudflared
    tag: "2026.7.3-host-metrics.1"
```

That is a maintainer fork carrying host-metrics patches, so the chart's own version
says nothing about it. Written inline, the tag would never be bumped and nothing
would report it as stale — it would simply sit there, looking deliberate. In a
`values.yaml` it is an ordinary dependency and Renovate opens a PR for it.

`external-dns` pins its UniFi webhook image the same way, and `photos` pins
`immich-server`. None of those are the chart version.

So the file is not a style preference — it is what puts these values under the
same automation as everything else.

## The hash is what makes the upgrade happen

A values change alters the ConfigMap's *contents*. If the name does not change
with them, nothing in the HelmRelease spec changes either — and helm-controller
has no event to act on. It compares `status.lastAttemptedConfigDigest` on its
next interval and upgrades then, so a correct change spends up to a full interval
looking like a failed deploy, and the way to stop waiting was to reconcile the
release by hand.

The hash removes that. A values edit changes the ConfigMap's name, the rewritten
`valuesFrom` changes the HelmRelease spec, and helm-controller upgrades on the
event. There is no separate step to remember and nothing to wait for.

This is a reversal. Both reasons the name used to be pinned have expired:

- **Orphan accumulation.** Under `prune: false` a hashed name left a ConfigMap
  behind on every edit, permanently. Nothing is in that state now — `crds` and
  `namespaces` are the only Kustomizations that do not prune, and neither
  generates values. See [how Flux is layered](flux-layering.md).
- **`valuesFrom` could not follow a changing name.** Kustomize rewrites name
  references only for kinds it knows, and a HelmRelease is not one. A
  `nameReference` teaches it the field, and one declared at a Flux Kustomization
  root applies to hashes generated in any component below it — so the config is
  written once, in `k8s/kustomize/helmrelease-values`, and each root names it.

It is a Component rather than a bare `configurations:` entry for a build reason:
kustomize refuses a configurations *file* outside the build root under the
default load restrictor. Flux runs without that restrictor and would accept it,
but `make validate` and `kubectl apply -k` would not, and a build that only works
in-cluster cannot be checked before merging. A component is referenced as a
directory, which is not restricted.

**Every HelmRelease is still kept at `interval: 5m`**, with no exceptions — the
*Interval* column in [Helm releases](../reference/helm-releases.md) should show
one value. It no longer sets how long a values change waits, which was its old
justification; what it still does is bound drift. A quiet chart is not a reason
to raise it: the interval costs a Helm dry-run diff, not an upgrade.
(`spec.chart.spec.interval` is a different knob — that one polls the chart source
and can stay high.)

### What it costs

`kubectl get cm` no longer prints the name as written in git. That was the real
benefit of pinning: the set of values ConfigMaps in a namespace read as exactly
the set declared, which matters most in a shared namespace like
`platform-network`, where traefik's three sit beside `values-cilium`,
`values-cloudflared` and `values-external-dns`. They still do, each with ten
characters of hash on the end.

Pruning keeps that honest — the old ConfigMap is garbage-collected in the same
apply that creates the new one, so what is in the namespace is still what git
declares, not a sediment of every edit.

## Why `values-<ReleaseName>`

The generator is named after the release it feeds, not after the component. A bare
`values` collides the moment a namespace gains a second release, and namespaces
here routinely have several — `values-postgres-sonarr` and `values-postgres-radarr`
sit side by side.

The hash is appended to that, so the convention is unchanged and so is what it
prevents: a second release in the same namespace still cannot collide with the
first, whatever their contents hash to.

Every release follows it. It is settled convention rather than preference,
arrived at after collisions.

## Layering, and secrets

`valuesFrom` is a list, and later entries win. Traefik uses that: both instances
read `values-traefik-common` first and then their own file, so the shared
configuration lives once and each instance only records its differences — its
ingress class and its LoadBalancer IP.

Secrets take the same path with `kind: Secret` instead. Three releases do this —
`cloudflared` and `pocket-id` twice — with an ExternalSecret rendering a
`values.yaml` key from Doppler. The credentials never enter git, and the release
does not need to know where they came from.

Those names are not hashed and are not rewritten: the Secret is rendered by an
ExternalSecret rather than generated here, so kustomize never sees its contents.
The `nameReference` deliberately covers `kind: ConfigMap` only — a rule matching
Secrets would find nothing to match against.

## Two traps this shape does not remove

**Helm deep-merges maps.** `{}` does not clear a chart default; only an explicit
`null` does. A values file that appears to disable something may be leaving it
exactly as the chart shipped it.

**A value at a path the chart does not read is silently inert.** Helm neither
warns nor fails, so the file reads as configuration while the app runs on
defaults. Expect this after every chart major. Read intent off the *rendered*
output — `helm template`, or the live ConfigMap — never off the values file:

```bash
kubectl -n <ns> get cm "$(kubectl -n <ns> get helmrelease <release> \
  -o jsonpath='{.spec.valuesFrom[-1:].name}')" -o jsonpath='{.data.values\.yaml}'
```

Reading the name off the release rather than typing it is the point: it is the
ConfigMap actually in effect, hash and all, so the output cannot be a file the
release stopped reading.

## The generators that keep a stable name

None of them feeds a HelmRelease: the k8up backup scripts in `karakeep`,
`mended-drum` and `vod-arr/cleanuparr`, and `recyclarr`'s config. They set
`disableNameSuffixHash` per generator rather than for the whole kustomization.

The reason is the mirror of the one above. A backup script is read at exec time
from the mounted ConfigMap, so an edit reaches the next run without the Pod
restarting — hashing it would roll the workload for a change that did not need
it. Where rolling the Pod *is* the point, the hash stays: `plex` generates its
`alloy-config` hashed for exactly that reason.

So the question is never "values or not" but what should happen when the contents
change. A HelmRelease needs an upgrade, and only a new name causes one.
