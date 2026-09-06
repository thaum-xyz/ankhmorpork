# Ankh-Morpork

Documentation for the [thaum.xyz][repo] home Kubernetes cluster — a k3s cluster
in a cupboard, managed entirely through Flux.

[repo]: https://github.com/thaum-xyz/ankhmorpork

<div class="grid cards" markdown>

-   :material-school:{ .lg .middle .quad-tutorial } __Tutorial__

    ---

    Learning-oriented. Start here if you have never deployed anything to this
    cluster. One guided path, guaranteed to work, no decisions to make.

    [:octicons-arrow-right-24: Deploy your first app](tutorial/index.md)

-   :material-wrench:{ .lg .middle .quad-howto } __How-to__

    ---

    Task-oriented. You know what you want and need the steps for *this* cluster.
    Runbooks live here too.

    [:octicons-arrow-right-24: Find a recipe](how-to/index.md)

-   :material-file-document-outline:{ .lg .middle .quad-reference } __Reference__

    ---

    Information-oriented. Storage classes, admission policies, ingress classes,
    the app inventory. Look things up, don't read it through.

    [:octicons-arrow-right-24: Look something up](reference/index.md)

-   :material-lightbulb-outline:{ .lg .middle .quad-explanation } __Explanation__

    ---

    Understanding-oriented. Why the cluster is built the way it is, and what was
    measured or learned to justify it.

    [:octicons-arrow-right-24: Understand the design](explanation/index.md)

</div>

## How this documentation is organised

This site follows [Diátaxis](https://diataxis.fr/). The four sections above are
document **types**, not subjects — the same component can appear in all four. A
page belongs in a section based on what the reader is *doing* when they open it:

|              | Practical       | Theoretical     |
| ------------ | --------------- | --------------- |
| **Studying** | Tutorial        | Explanation     |
| **Working**  | How-to          | Reference       |

Each section states its own admission test. Read it before adding a page there —
the framework only pays for itself if the boxes stay honest.

## Where documentation lives

Two prior doc sets for this cluster died after being moved away from the code
they described: `docs/` went to a private Logseq, and the runbooks went to
[thaum-xyz/runbooks][rb], which last received a commit in November 2021. What
survived instead was everything that stayed inside the repository — the per-app
READMEs, `AGENTS.md`, the deployment skill.

[rb]: https://github.com/thaum-xyz/runbooks

So the rule here is proximity:

- **This site is built from `docs/` in the `ankhmorpork` repository.** The source
  is plain Markdown with no front matter, so every page stays readable on
  github.com and shows up in the diff that invalidates it. Only the *rendering*
  leaves the repo.
- **Per-app documentation stays next to its manifests**, at
  `k8s/apps/<app>/README.md`, for the same reason.
- **Nothing here contains secrets, credentials, or break-glass paths.** The
  repository is public on purpose. Anything failing that test does not belong on
  this site — see [what stays private](explanation/index.md).

!!! tip "Found something wrong?"

    Every page has an :material-pencil: edit link in the top right that opens it
    directly in the GitHub editor. Fixing a stale sentence should cost less than
    tolerating it.
