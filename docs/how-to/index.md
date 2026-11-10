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

A runbook is a how-to written for someone at 2am. It has its own shape and its
own directory — see [Runbooks](#runbooks).

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
- [Silence alerts for maintenance](silence-alerts-for-maintenance.md) — and the
  one matcher that must never match

## Runbooks

A runbook is entered from a firing alert, not from a goal. One page per alert,
in `docs/how-to/runbooks/`, named exactly after the alert, so the alert's
`runbook_url` follows from its name:
`https://docs.thaum.xyz/how-to/runbooks/<AlertName>/`.

Every runbook has the same four sections, in this order:

| Section | Answers |
| --- | --- |
| Meaning | what is true when the alert fires, and which labels identify the object |
| Impact | what is broken or at risk, and how that changes with time |
| Diagnosis | numbered steps with a command each, ending in a cause |
| Mitigation | the fix for each cause |

A runbook describes the condition and what to do about it, and leaves out how
its alert is delivered. Severity and routing are set in the rule and in
Alertmanager's configuration, and change without the page.

`make docs-lint` fails on a `runbook_url` that points at this site with no page
behind it, and warns about a runbook no alert links to.

- [drbdResourceWithNoUpToDateReplicas](runbooks/drbdResourceWithNoUpToDateReplicas.md)
  — a piraeus volume has no replica DRBD will serve from, and cannot be mounted
- [FluxCDReconciliationFailure](runbooks/FluxCDReconciliationFailure.md) — a
  Kustomization, HelmRelease or source has stopped reconciling
- [KuredRebootRequired](runbooks/KuredRebootRequired.md) — a node has wanted a
  reboot for over a week and kured has not managed one

## Not written yet

Open documentation work is tracked as
[issues labelled `documentation`](https://github.com/thaum-xyz/ankhmorpork/issues?q=is%3Aissue+is%3Aopen+label%3Adocumentation).
Most alerts that carry a `runbook_url` point at
[runbooks.thaum.xyz](https://runbooks.thaum.xyz/), a site whose repository was
last touched in 2021 and which has no page for many of them; replacing those is
[#1287](https://github.com/thaum-xyz/ankhmorpork/issues/1287).
