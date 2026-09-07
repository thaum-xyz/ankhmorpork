---
name: docs-authoring
description: Write or edit pages under docs/ in thaum-xyz/ankhmorpork (published at docs.thaum.xyz). Use when adding a page, moving content between sections, documenting a new component, storage class, policy or convention, updating a how-to after a manifest change, or when asked whether something should be documented and where. Covers which Diátaxis section a page belongs in, what must be generated rather than typed, the prose patterns that have gone stale before, and the lint and build commands to run before pushing.
---

# Writing documentation

Two earlier doc sets for this cluster died of staleness. Every rule here exists
to make a page either mechanically checkable or obviously dated when it is wrong.

## Where a fact lives

One home per fact. Every other page links to it.

| Fact | Home | Everything else does |
| --- | --- | --- |
| which apps, namespaces, hosts exist | `docs/reference/apps.md` *(generated)* | link |
| what admission does, and to what | `docs/reference/admission-policies.md` *(generated)* | link |
| Kustomization interval, prune, wait, dependsOn | `docs/reference/flux-kustomizations.md` *(generated)* | link |
| which chart, from where, values source, interval | `docs/reference/helm-releases.md` *(generated)* | link |
| chart or image **version** | the manifest itself | link to the file, never quote it |
| storage class capabilities and measured numbers | `docs/reference/storage-classes.md` | link |
| ingress classes, issuers, DNS behaviour | `docs/reference/ingress.md` | link |
| annotation and label contracts | `docs/reference/annotations.md` | link |
| the reconcile order and why it matters | `docs/explanation/flux-layering.md` | one sentence + link |
| per-app quirks | `k8s/apps/<app>/README.md` | link |
| traps an agent hits mid-change | `.claude/skills/app-deployment/SKILL.md` | link |

If a fact has no home yet, give it one before quoting it twice.

## Which section

Decide by what the reader is *doing*, not what the page is about. Each section's
`index.md` has an admission checklist; the page must pass all of it.

| Reader is… | Section | Shape |
| --- | --- | --- |
| learning, first time, no decisions | `tutorial/` | one path, every choice made for them, ends with cleanup |
| mid-task, knows the goal | `how-to/` | numbered steps, one command block each, "it depends" allowed |
| looking something up | `reference/` | tables and definition lists, no verbs of persuasion |
| away from the keyboard, asking why | `explanation/` | may argue, compare, admit uncertainty |

Rationale in a how-to or reference page is a smell: cut it to one sentence and
link the explanation. A step in an explanation is the same smell in reverse.

## What goes stale, and what to do instead

These are the patterns that have actually rotted here. `make docs-lint` warns on
most of them.

| Pattern | Why it rots | Write instead |
| --- | --- | --- |
| a count — "24 components", "all 47", "eleven databases" | changes with the next PR, nothing reminds you | the fact without the number, plus a link to the generated page that carries it |
| a version — `oauth2-proxy:v7.15.3`, "chart 0.5.0" | Renovate bumps the manifest, not the sentence | in a copy-paste block: keep it (Renovate now tracks `image:` lines in docs). In prose: name the manifest, drop the number |
| a live-cluster measurement — "58 rules", "69 ExternalSecrets" | not derivable from git, nobody re-counts | drop it, or date it ("when this was set up, …") |
| "currently", "planned", "not yet", "today", "open item" | true on the day, never revisited | state the fact; put plans in an issue, not a page |
| a path to something outside the repo | no reader can follow it | say it is outside the repo, or bring the method in |
| a link to a page that does not exist yet | a broken promise | write the page or drop the link |
| a namespace, policy or class **name** typed from memory | the lint checks these against manifests | run `make docs-lint` |

Dates are fine on measurements and on records of things that happened. They
are not fine as a substitute for keeping a claim current.

## Generated pages

Four reference pages are written by `hack/generate-docs-reference.py` and
carry a banner saying so. Never edit them; edit the script.

```bash
make docs-reference          # regenerate
make docs-reference-check    # what CI runs; fails if you forgot
```

When a new kind of fact is derivable from the manifests, extend the generator
rather than typing a table. The bar: if a PR to `k8s/` could invalidate it,
it should be generated.

## Before pushing

```bash
make docs-reference-check    # generated pages are fresh
make docs-lint               # links, paths, names; warnings for stale-prone prose
make docs-build              # the site renders (Zensical is alpha; rendering does change)
```

Fix every error. Read every warning and either fix it or be able to say why
the sentence is right anyway. A new page must be added to the `nav` in
`zensical.toml`; the lint fails on orphans.

## Style, in five rules

1. **Lead with the fact.** First sentence of a page or section says what is
   true; the reasoning follows.
2. **Tables for anything with more than two attributes.** Reference pages are
   mostly tables. How-tos are mostly numbered steps with a command each.
3. **One code block per step, copy-pasteable.** Placeholders in angle brackets:
   `<namespace>`, `<release>`. Real names only when the reader must use exactly
   that name.
4. **Admonitions for the one thing that will bite**, not for emphasis. If a
   page has three `!!! danger` blocks, two of them are paragraphs.
5. **Cross-link, don't restate.** A fact repeated on two pages is a fact that
   will disagree with itself. The explanation gets the argument; the how-to
   gets the sentence and the link.

## Not on this site

Secrets, credentials, break-glass procedures, and anything that only makes
sense with cluster access nobody else has. The repository is public.
