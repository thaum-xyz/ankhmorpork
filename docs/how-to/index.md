# How-to { .quad-howto }

## What belongs here

A how-to is a **recipe** for a reader who already knows what they want. It starts
from a realistic situation, not a clean slate, and it is allowed to say "it
depends" — that is the difference from a [tutorial](../tutorial/index.md).

Admission test:

- [ ] It answers "how do I …?" for a goal the reader already has.
- [ ] It is a sequence of steps, not an explanation. Rationale goes in
      [Explanation](../explanation/index.md); tables of options go in
      [Reference](../reference/index.md).
- [ ] It is specific to *this* cluster. If upstream documentation already covers
      it, link out instead of restating it.

Runbooks are how-to documents written for someone at 2am, and belong in this
section once migrated.

## Available now

- [Expose an app on an ingress](expose-an-app.md) — which class, and why a public
  host needs two Ingresses
- [Require a login](require-a-login.md) — pocket-id, natively or through
  oauth2-proxy
- [Log in with kubectl](log-in-with-kubectl.md) — passkey instead of a client
  certificate, and how pocket-id groups become RBAC subjects
- [Choose a storage class](choose-a-storage-class.md) — which class a workload
  belongs on, in the order the questions actually matter
- [Roll a workload when its ConfigMap changes](reload-on-configmap-change.md)

## Not written yet

Open documentation work is tracked as
[issues labelled `documentation`](https://github.com/thaum-xyz/ankhmorpork/issues?q=is%3Aissue+is%3Aopen+label%3Adocumentation).
Two runbooks are served from [runbooks.thaum.xyz](https://runbooks.thaum.xyz/), a
site whose repository was last touched in 2021; bringing them here is
[#1364](https://github.com/thaum-xyz/ankhmorpork/issues/1364).
