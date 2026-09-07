# Require a login { .quad-howto }

Every ingress class in this cluster is unauthenticated. `private` limits *where* a
request can come from, not *who* is making it — anything on the house network
reaches it. Authentication is a separate decision, and it is
[pocket-id](https://login.krupa.net.pl) in both cases below.

## First: does the app have its own OIDC support?

That decides everything. Check its documentation before writing any manifests —
the two paths differ completely and only one is worth the effort.

## Path A — the app supports OIDC

Create the client in pocket-id, put its credentials in Doppler as
`<APP>_OIDC_CLIENT_ID` / `<APP>_OIDC_CLIENT_SECRET`, and pull them in:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: oidc-client
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: doppler-auth-api
  data:
    - remoteRef:
        key: MYAPP_OIDC_CLIENT_ID
      secretKey: clientID
    - remoteRef:
        key: MYAPP_OIDC_CLIENT_SECRET
      secretKey: clientSecret
```

Then wire it into the app however it expects. The issuer is
`https://login.krupa.net.pl`, and most apps want its discovery document at
`https://login.krupa.net.pl/.well-known/openid-configuration`.

Nothing else is needed — no proxy, no extra Ingress. `mealie`, `grafana` and
`open-webui` all work this way.

## Path B — the app has no login of its own

Put **oauth2-proxy** in front of it and point the Ingress at the proxy, never at
the app's Service. The proxy becomes the authentication boundary; the app stays
unauthenticated and unreachable except through it.

Two shapes, both in use here:

- **A sidecar** in the app's Pod, with the app bound to localhost so it is never
  published — `stirling-pdf`.
- **A standalone Deployment**, when the chart offers no `extraContainers` and
  hardcodes its Service target — `changedetection`.

Prefer the sidecar. It removes any way to reach the app without passing the proxy.

### The proxy

```yaml
containers:
  - name: oauth2-proxy
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.15.3
    args:
      - --provider=oidc
      - --oidc-issuer-url=https://login.krupa.net.pl
      - --redirect-url=https://myapp.krupa.net.pl/oauth2/callback
      - --http-address=0.0.0.0:4180
      - --upstream=http://127.0.0.1:8080
      - --email-domain=*
      - --scope=openid email profile
      - --code-challenge-method=S256
      - --reverse-proxy=true
      - --cookie-secure=true
      - --skip-provider-button=true
    env:
      - name: OAUTH2_PROXY_CLIENT_ID
        valueFrom:
          secretKeyRef: { name: myapp-oidc, key: clientID }
      - name: OAUTH2_PROXY_CLIENT_SECRET
        valueFrom:
          secretKeyRef: { name: myapp-oidc, key: clientSecret }
      - name: OAUTH2_PROXY_COOKIE_SECRET
        valueFrom:
          secretKeyRef: { name: myapp-oauth2-cookie, key: password }
    resources:
      requests:
        cpu: 10m
        memory: 32Mi
```

Four of those arguments are not obvious:

- **`--email-domain=*`** is mandatory, not permissive sloppiness. Left unset it
  defaults to allowing *nothing* and rejects every address.
- **`--reverse-proxy=true`** — Traefik and cloudflared are both in front, so
  `X-Forwarded-*` must be trusted or redirects break.
- **`--code-challenge-method=S256`** — pocket-id advertises PKCE and oauth2-proxy
  warns when it is off.
- **`--skip-provider-button=true`** sends users straight to pocket-id instead of an
  interstitial page with one button on it.

### The cookie secret

It only needs to be 32 stable bytes, so generate it in-cluster rather than storing
it anywhere. `refreshInterval: "0"` mints it once — a refresh would invalidate
every live session:

```yaml
apiVersion: generators.external-secrets.io/v1alpha1
kind: Password
metadata:
  name: myapp-oauth2-cookie
spec:
  length: 32
  digits: 8
  symbols: 0
  noUpper: false
  allowRepeat: true
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: myapp-oauth2-cookie
spec:
  refreshInterval: "0"
  target:
    name: myapp-oauth2-cookie
  dataFrom:
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: Password
          name: myapp-oauth2-cookie
```

### Point the Ingress at the proxy

Change the backend to the proxy's port — `4180` for a standalone Deployment, or
the sidecar's port on the app's own Service. Both the `public` and `cloudflare`
Ingresses must point there. An Ingress still aimed at the app bypasses
authentication entirely, and nothing will warn you.

### Probing an app behind the proxy

Adding `ingress.thaum.xyz/probe: enabled` and stopping there produces a probe
that cannot fail. The blackbox target becomes the bare host, the proxy redirects
it into pocket-id, `--skip-provider-button` sends it straight to `/interaction`,
and pocket-id answers 200. blackbox follows redirects and `http_2xx` asserts
nothing about the body, so the probe's success criterion is *pocket-id is up* —
it stays green with the app it names completely down. That is worse than no
probe, because it looks like coverage.

Both proxied apps here were caught by it: `pdf` had the defect for real, and
`change` would have inherited it.

So pick a path the app serves itself and exempt it:

```yaml
- --skip-auth-route=GET=^/actuator/health$
```

Three things to check before choosing one:

- **It must be answered by the app process**, not by a static asset and not by
  the proxy. `/ping` and `/ready` are oauth2-proxy's own endpoints, so probing
  them measures the proxy.
- **It must be safe to serve unauthenticated**, because exempting it publishes
  it. Prefer counts and status over anything that lists content — `/` is usually
  the app's data.
- **It must not change anything.** changedetection's `/worker-health` restarts
  dead workers; a probe must not repair what it measures.

The exemption matches `req.URL.Path`, not the request URI, so a query string in
`ingress.thaum.xyz/probe-uri` is not part of the regex.

Verify with `probe_http_redirects == 0` on the new target — a probe still
redirecting is a probe still landing on the login page.

## Authorisation stays in pocket-id

Restrict the **client** to groups in pocket-id. It then refuses to issue a token
for anyone outside them, and the proxy never sees those users at all.

Do not add a second allow-list in oauth2-proxy. It is one more thing to drift, and
the one that is easy to forget is the one that is too permissive.
