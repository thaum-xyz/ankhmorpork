# Reference { .quad-reference }

## What belongs here

Reference is a **map**, consulted mid-task and never read through. It describes
the machinery and does nothing else: no instruction, no persuasion, no worked
examples.

Admission test:

- [ ] The reader arrives already knowing what they are looking for.
- [ ] It is structured to match the thing it describes — one section per storage
      class, one row per policy — not structured as an argument.
- [ ] It is neutral. The moment a page starts justifying a choice, that part
      belongs in [Explanation](../explanation/index.md).

!!! tip "Prefer generated reference"

    Reference rots faster than anything else here and benefits least from prose.
    The app inventory, ingress hosts, namespaces and storage classes are all
    derivable from the manifests — generate them in CI rather than typing them.

## Available now

- [Applications](apps.md) — every app, its namespace, its Flux Kustomization and
  its hostnames *(generated)*
- [Admission policies](admission-policies.md) — what Kyverno enforces, and which
  rules only warn *(generated)*
- [Ingress and certificates](ingress.md) — the three classes, the two issuers,
  and what external-dns publishes
- [Storage classes](storage-classes.md) — capabilities, access modes, node
  affinity and measured ceilings
- [Annotations and labels](annotations.md) — keys this cluster gives meaning to,
  and two that look load-bearing but are not
- [Charts and images](charts.md) — the two sibling repositories, what they hold,
  and where their generated reference lives
- [UPS Modbus register map](../ups/modbus-register-map.md)
