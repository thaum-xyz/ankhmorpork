# Tutorial { .quad-tutorial }

!!! warning "Placeholder"

    The site scaffold is in place; this section has no content yet.

## What belongs here

A tutorial is a **lesson**. The reader is learning the cluster, and the app they
deploy is a means to that end — they do not care about it and will delete it at
the end.

Admission test, all four must hold:

- [ ] It is safe to follow start to finish with no prior knowledge of this cluster.
- [ ] It **succeeds every time**. No "depending on your setup", no branches.
- [ ] It contains **no decisions**. Every choice is made for the reader, with the
      reasoning deferred to [Explanation](../explanation/index.md) and the
      alternatives to [Reference](../reference/index.md).
- [ ] It ends with the reader having seen something work.

That last constraint is why there is only ever going to be one tutorial here.
Decision tables — pick a StorageClass, pick an ingress class — are exactly what a
tutorial must not contain. They are how-to and reference material.

## Planned

- **Deploy your first app** — a throwaway app end to end: manifests under
  `k8s/apps/`, a Flux Kustomization under `k8s/flux/apps/`, `make validate`,
  merge, reconcile, watch it come up, delete it again.

Individual applications (Plex, Immich, Mealie) will never have a tutorial. Nobody
learns this cluster *through* Mealie. Those get reference and how-to instead.
