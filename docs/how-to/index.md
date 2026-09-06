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

- [Choose a storage class](choose-a-storage-class.md) — which class a workload
  belongs on, in the order the questions actually matter
- [Roll a workload when its ConfigMap changes](reload-on-configmap-change.md)

## Planned

- Expose an app on an ingress
- Rotate a secret
- Recover a Postgres cluster from backup
- Drain and reboot a node outside the kured cycle
- Debug a Flux reconcile that reports success but changes nothing

## Open item: the existing runbooks

[runbooks.thaum.xyz](https://runbooks.thaum.xyz/) is still serving, from a
repository whose last commit was 2021-11-05. Its content predates most of this
cluster. It needs to be triaged into this section and the old site retired —
tracked at `docs/runbooks/README.md`, which currently just points at it.
