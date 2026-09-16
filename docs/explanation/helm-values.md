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
generatorOptions:
  disableNameSuffixHash: true
  labels:
    reconcile.fluxcd.io/watch: Enabled
```

```yaml
# release.yaml
spec:
  valuesFrom:
    - kind: ConfigMap
      name: values-myapp
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

## The name is stable, and the label is what pays for that

`disableNameSuffixHash: true` gives the ConfigMap a fixed name instead of
`values-myapp-7f9c2b4h8d`, so `valuesFrom.name` can reference it directly and
`kubectl get cm` prints what git declares.

On its own that would cost something real. A values change alters the
ConfigMap's *contents* but not its name, so nothing in the HelmRelease spec
changes and helm-controller has no event to act on — it would compare
`status.lastAttemptedConfigDigest` on its next interval and upgrade then, up to
five minutes after a correct change, which looks exactly like a failed deploy.

`reconcile.fluxcd.io/watch: Enabled` is what removes that. helm-controller
watches labelled ConfigMaps and Secrets referenced in `valuesFrom` and
reconciles when their contents change, so the upgrade happens on the edit. On
this cluster the reconcile lands about 300ms after the write.

It needs no controller flag: the `--disable-config-watchers` feature gate is off
by default and `--watch-configs-label-selector` defaults to that exact label.
The alternative is `--watch-configs-label-selector=owner!=helm`, which watches
every referenced object without labelling any of them — and makes
helm-controller cache every ConfigMap and Secret in the cluster. That is the
same trade [rolling a workload when its ConfigMap changes](configmap-autoreload.md#why-not-secrets)
refuses for Kyverno, and it is refused here for the same reason.

**Every HelmRelease is kept at `interval: 5m`**, with no exceptions — the
*Interval* column in [Helm releases](../reference/helm-releases.md) should show
one value. That interval no longer sets how long a values change waits, which
was its original justification; what it still does is bound drift. A quiet chart
is not a reason to raise it: the interval costs a Helm dry-run diff, not an
upgrade. (`spec.chart.spec.interval` is a different knob — that one polls the
chart source and can stay high.)

### What stable names buy beyond that

Under `prune: true` an orphaned `values-myapp-7f9c2b4h8d` is garbage-collected on
the next reconcile, so a hash would cost churn rather than accumulation — every
Kustomization that generates a values ConfigMap prunes, and the two that do not
are layers that generate none. See
[how Flux is layered](flux-layering.md) for which those are.

What the stable name still buys is that the set of values ConfigMaps in a
namespace is exactly the set declared in git. `traefik` holds three —
`values-traefik-common`, `values-traefik-public`, `values-traefik-private` — and
that is what `kubectl get cm` shows, not three plus a sediment of every edit
since the component was created. In a shared namespace that matters more than
the churn did: `platform-network` holds those three beside `values-cilium`,
`values-cloudflared` and `values-external-dns`, and a reader can tell at a glance
that each belongs to something.

## Why `values-<ReleaseName>`

The generator is named after the release it feeds, not after the component. A bare
`values` collides the moment a namespace gains a second release, and namespaces
here routinely have several — `values-postgres-sonarr` and `values-postgres-radarr`
sit side by side.

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

## Two traps this shape does not remove

**Helm deep-merges maps.** `{}` does not clear a chart default; only an explicit
`null` does. A values file that appears to disable something may be leaving it
exactly as the chart shipped it.

**A value at a path the chart does not read is silently inert.** Helm neither
warns nor fails, so the file reads as configuration while the app runs on
defaults. Expect this after every chart major. Read intent off the *rendered*
output — `helm template`, or the live ConfigMap — never off the values file:

```bash
kubectl -n <ns> get cm values-<release> -o jsonpath='{.data.values\.yaml}' | grep <key>
```

That is also the check worth running when a release did not pick something up:
it confirms the ConfigMap holds what you meant, rather than assuming the
Kustomization regenerated it.

## The generators that are neither stable nor labelled

`plex` generates an `alloy-config` ConfigMap without `disableNameSuffixHash`, and
that is not an oversight — it feeds a Deployment rather than a HelmRelease, and
there the changing name is the point: it is what rolls the Pod.

The k8up backup scripts in `karakeep`, `mended-drum` and `vod-arr/cleanuparr`
and `recyclarr`'s config sit at the third corner: stable, and unlabelled. No
HelmRelease reads them, so a watch would fire for nothing, and each is read at
exec time from the mounted ConfigMap, so an edit reaches the next run with
nothing restarting.

The question is never "values or not" but what has to happen when the contents
change. A mounted file read at exec time needs nothing. A Pod that reads its
config at startup needs a new ConfigMap name. A HelmRelease needs an upgrade,
and the label is what asks for one.
