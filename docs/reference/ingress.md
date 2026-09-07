# Ingress classes and certificates { .quad-reference }

To put an app on an ingress, use [expose an app](../how-to/expose-an-app.md).
The tables below are generated from the Traefik, cloudflared, cert-manager and
external-dns manifests; the prose between them is not.

## Classes

<!-- generated:ingress-classes -->
<!-- This block is written by hack/generate-docs-reference.py; edit the
     manifests it reads, not the table. -->
| Class | Controller chart | Address | Default class | Source |
| --- | --- | --- | --- | --- |
| `cloudflare` | `cloudflare-tunnel-ingress-controller` | Cloudflare tunnel `ankhmorpork-tunnel` | no | [`k8s/platform/network/cloudflared/values.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/network/cloudflared/values.yaml) |
| `private` | `traefik` | `192.168.50.130` | no | [`k8s/platform/network/traefik/private/values.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/network/traefik/private/values.yaml) |
| `public` | `traefik` | `192.168.50.129` | **yes** | [`k8s/platform/network/traefik/public/values.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/network/traefik/public/values.yaml) |
<!-- /generated:ingress-classes -->

`private` is reachable from the LAN only. `public` is reachable from the LAN and,
paired with a `cloudflare` Ingress for the same host, from outside — the how-to
has the pairing and the reason. The two Traefik instances are separate
HelmReleases with their own LoadBalancer IP, not one controller with two
entrypoints.

An Ingress that omits `ingressClassName` lands on the default class. Do not rely
on that — the admission policy requires the field to be set explicitly.

## Certificate issuers

<!-- generated:cluster-issuers -->
<!-- This block is written by hack/generate-docs-reference.py; edit the
     manifests it reads, not the table. -->
| Issuer | Challenge | ACME server | Source |
| --- | --- | --- | --- |
| `letsencrypt-dns01` | DNS-01 (cloudflare) | Let's Encrypt, production | [`k8s/platform/security/cert-manager/additional/issuer-acme-dns01-cloudflare.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/security/cert-manager/additional/issuer-acme-dns01-cloudflare.yaml) |
| `letsencrypt-prod` | DNS-01 (cloudflare) | Let's Encrypt, production | [`k8s/platform/security/cert-manager/additional/issuer-acme-http.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/security/cert-manager/additional/issuer-acme-http.yaml) |
<!-- /generated:cluster-issuers -->

Both issuers solve the same challenge through Cloudflare, so a hostname does not
have to be reachable before its certificate is issued and wildcards work on
either. They differ only in the ACME account key behind them; `letsencrypt-prod`
is the convention. Both are accepted by the admission policy; anything else is
rejected. Set one with the `cert-manager.io/cluster-issuer` annotation.

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

<!-- generated:external-dns -->
<!-- This block is written by hack/generate-docs-reference.py; edit the
     manifests it reads, not the table. -->
| Setting | Value |
| --- | --- |
| Provider | `webhook` |
| Domains it will touch | `thaum.xyz`, `krupa.net.pl` |
| Policy | `sync` |
| Ownership | `txt` registry, `txtOwnerId: thaum.xyz`, `txtPrefix: k8s.` |
| Fallback name for a Service with no host | `{{.Name}}.{{.Namespace}}.ankhmorpork.thaum.xyz` |
| Source | [`k8s/platform/network/external-dns/values.yaml`](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/network/external-dns/values.yaml) |
<!-- /generated:external-dns -->

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

Every hostname served is listed in [applications](apps.md), generated from the
Ingress manifests and the chart values.
