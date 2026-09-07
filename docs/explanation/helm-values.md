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

## The name has to be stable, and that has a cost

`disableNameSuffixHash: true` gives the ConfigMap a fixed name instead of
`values-myapp-7f9c2b4h8d`. Without it, `valuesFrom.name` would have to reference a
name that changes on every edit.

The consequence is the awkward part. A values change alters the ConfigMap's
*contents* but not its name — so nothing in the HelmRelease spec changes, and
helm-controller sees no event to act on. It notices only via
`status.lastAttemptedConfigDigest` on its next interval.

Two things follow from that, and both are deliberate:

- **Every HelmRelease is kept at `interval: 5m`**, with no exceptions — the
  *Interval* column in [Helm releases](../reference/helm-releases.md) should show
  one value. That interval is the ceiling on
  how long a values-only change can sit looking like a failed deploy. A quiet chart
  is not a reason to raise it: the interval costs a Helm dry-run diff, not an
  upgrade. (`spec.chart.spec.interval` is a different knob — that one polls the
  chart source and can stay high.)
- **A values-only change needs its release reconciled explicitly.** See
  [how Flux is layered](flux-layering.md) for the ordering that goes with it.

The hash suffix would trigger the upgrade immediately, at the cost of a new
ConfigMap on every edit. Stable names are the trade; reconciling the release is
the price.

### And where nothing prunes, that cost is permanent

Under `prune: true` an orphaned `values-myapp-7f9c2b4h8d` is garbage-collected on
the next reconcile, so the hash costs churn but not accumulation.

The Kustomizations that do not prune include five platform components
that generate values ConfigMaps — `cilium`, `flux-system`, `topolvm`,
`piraeus-datastore` and `traefik`. See
[how Flux is layered](flux-layering.md) for why those five are exempt. There,
nothing would ever remove the old ConfigMap: every values edit would leave one
behind, permanently, in exactly the components whose namespaces are hardest to
reason about when something is wrong.

Stable names mean the set of values ConfigMaps in a namespace is exactly the set
declared in git. `traefik` holds three — `values-common`, `values-public`,
`values-private` — and that is what `kubectl get cm` shows, not three plus a
sediment of every edit since the component was created.

## Why `values-<ReleaseName>`

The generator is named after the release it feeds, not after the component. A bare
`values` collides the moment a namespace gains a second release, and namespaces
here routinely have several — `values-postgres-sonarr` and `values-postgres-radarr`
sit side by side.

Every release follows it. It is settled convention rather than preference,
arrived at after collisions.

## Layering, and secrets

`valuesFrom` is a list, and later entries win. Traefik uses that: both instances
read `values-common` first and then their own file, so the shared configuration
lives once and each instance only records its differences — its ingress class and
its LoadBalancer IP.

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

That is also the check worth running before reconciling a release: it confirms the
ConfigMap actually changed, rather than assuming the Kustomization regenerated it.

## The one generator that keeps its hash

`plex` generates an `alloy-config` ConfigMap without `disableNameSuffixHash`. That
is not an oversight — it feeds a Deployment rather than a HelmRelease, and there
the changing name is the point: it is what rolls the Pod when the config changes.
The stable-name argument applies to values files, not to every generator.
