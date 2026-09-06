# Expose an app on an ingress { .quad-howto }

Decide who should reach it, then write the Ingress. Classes, issuers and DNS
behaviour are in [ingress classes and certificates](../reference/ingress.md).

## 1. Who should reach it?

| Audience | What to create |
| --- | --- |
| Only the house LAN | one `private` Ingress |
| Anyone, from anywhere | a `public` Ingress **and** a `cloudflare` Ingress, same host |

There is no single "public" Ingress that works both inside and outside. The pair
is required, and section 3 explains why.

## 2. LAN only

Host it under `ankhmorpork.thaum.xyz`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: private
  rules:
    - host: myapp.ankhmorpork.thaum.xyz
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  name: http
  tls:
    - hosts:
        - myapp.ankhmorpork.thaum.xyz
      secretName: myapp-tls
```

That is the whole job. `external-dns` publishes the name to UniFi's resolver and
`cert-manager` obtains the certificate; neither is mentioned in the manifest.

## 3. Reachable from outside

Use a `krupa.net.pl` host, and write **two** Ingresses for it. The second differs
only in class, and carries no TLS block or issuer:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-cloudflare
spec:
  ingressClassName: cloudflare
  rules:
    - host: myapp.krupa.net.pl
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  name: http
```

Both are needed, for opposite reasons:

- **Without the `cloudflare` one**, off-LAN clients still resolve the name — the
  `*.krupa.net.pl` wildcard sends them to Cloudflare — but the tunnel has no route
  for it, so they get nothing.
- **Without the `public` one**, external-dns publishes only the tunnel CNAME
  (`*.cfargotunnel.com`), which resolves nowhere internally. The house resolver
  hands out a name with no usable address.

Keep the two names distinct (`myapp` and `myapp-cloudflare`). If a Helm chart also
renders an Ingress, set `ingress.enabled: false` in its values and own both here —
a chart upgrade that disables its Ingress will otherwise delete any Ingress
sharing that name.

## 4. Validate

```bash
git add k8s/apps/myapp
make validate
```

`validate-ingress-contract` **denies** on apply, so a mistake here is a failed
reconcile rather than a warning. The four that catch people:

- `ingressClassName` missing — the default class exists but the policy still
  requires the field
- the deprecated `kubernetes.io/ingress.class` **annotation** used instead
- a `public` or `private` Ingress with no `spec.tls`
- a TLS entry with no `secretName`

## 5. After it rolls out

The certificate takes a minute or two:

```bash
kubectl -n myapp get certificate -w
```

Once `READY` is `True`, the host answers. If it does not:

```bash
# Did external-dns publish it?
kubectl -n network logs deploy/external-dns | grep myapp

# Did the ingress controller accept it?
kubectl -n myapp describe ingress myapp
```

A name that resolves but times out from off-LAN is almost always the missing
`cloudflare` Ingress from section 3.

## Requiring a login

Neither class authenticates anything. To put a login in front, see
[require a login](require-a-login.md).
