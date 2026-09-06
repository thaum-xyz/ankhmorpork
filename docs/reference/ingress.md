# Ingress classes and certificates { .quad-reference }

Three ingress classes, two certificate issuers. To put an app on one, use
[expose an app](../how-to/expose-an-app.md).

## Classes

| Class | Controller | Reaches | Address |
| --- | --- | --- | --- |
| `public` | Traefik | LAN, and off-LAN only via a paired `cloudflare` Ingress | `192.168.50.129` |
| `private` | Traefik | LAN only | `192.168.50.130` |
| `cloudflare` | `strrl.dev/cloudflare-tunnel-ingress-controller` | the internet, through the `ankhmorpork-tunnel` | tunnel CNAME |

`public` is the cluster's **default** IngressClass (`isDefaultClass: true`), so an
Ingress that omits `ingressClassName` gets it. Do not rely on that — the admission
policy requires the field to be set explicitly.

Both Traefik instances are separate HelmReleases with their own LoadBalancer IP,
not one controller with two entrypoints.

## Certificate issuers

| Issuer | Use |
| --- | --- |
| `letsencrypt-prod` | the default; HTTP-01 |
| `letsencrypt-dns01` | when HTTP-01 cannot work — wildcards, or a name not yet reachable |

Both are accepted by the admission policy; anything else is rejected. Set one with
the `cert-manager.io/cluster-issuer` annotation.

`cloudflare` Ingresses need no issuer and no TLS block: the tunnel terminates TLS
at Cloudflare's edge.

## What admission enforces

`validate-ingress-contract` **denies** an Ingress that fails any of these. Full
rule text in [admission policies](admission-policies.md).

- `spec.ingressClassName` is one of `public`, `private`, `cloudflare`
- the deprecated `kubernetes.io/ingress.class` **annotation** is absent
- `public` and `private` Ingresses set `spec.tls`
- `public` and `private` Ingresses use an approved `cert-manager.io/cluster-issuer`
- every TLS entry sets a non-empty `secretName`

## DNS

`external-dns` writes records into **UniFi's resolver** — the house's internal
DNS, not a public zone.

| Setting | Value |
| --- | --- |
| Domains it will touch | `thaum.xyz`, `krupa.net.pl` |
| Policy | `sync` — it deletes records it owns when the Ingress goes |
| Ownership | TXT registry, `txtOwnerId: thaum.xyz`, `txtPrefix: k8s.` |
| Fallback name | `{{.Name}}.{{.Namespace}}.ankhmorpork.thaum.xyz` |

From a `cloudflare` Ingress, external-dns publishes the **tunnel CNAME**
(`*.cfargotunnel.com`), which resolves nowhere on the LAN. This is why a
`cloudflare` Ingress alone leaves a name that the internal resolver hands out with
no usable address.

Public names resolve off-LAN through the `*.krupa.net.pl` wildcard CNAME pointing
at Cloudflare. That means an off-LAN client reaching a `private`-only host will
resolve it, arrive at Cloudflare, and get nothing — the tunnel has no route for
it.

## Host naming

| Pattern | Meaning |
| --- | --- |
| `<name>.ankhmorpork.thaum.xyz` | internal, `private` class |
| `<name>.krupa.net.pl` | external, `public` + `cloudflare` pair |

Every hostname currently served is listed in [applications](apps.md), generated
from the manifests.
