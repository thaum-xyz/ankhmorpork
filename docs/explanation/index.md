# Explanation { .quad-explanation }

## What belongs here

Explanation is **discussion**. It is the only section that may argue, compare,
admit uncertainty, or describe something that was tried and rejected. It is read
away from the keyboard.

Admission test:

- [ ] It answers "why is it like this?" rather than "how do I?".
- [ ] It is useful to someone who is not currently doing anything.
- [ ] It can be read in any order relative to the rest of the site.

This is where hard-won knowledge goes to stay found: measurements, trade-offs,
and the reasoning behind conventions that otherwise look arbitrary. Most of it
currently exists only in commit messages, per-app READMEs and
`.claude/skills/app-deployment/SKILL.md`.

## Planned

- Why observability is split by role rather than by stack
- Why Helm values live in `values.yaml` rather than inline in a HelmRelease
- What stays private, and why the rest of this is public

## Available now

- [How Flux is layered](flux-layering.md) — bootstrap, platform, apps, and why
  reconciling in the wrong order reports success
- [Why storage is split the way it is](storage-durability.md) — and how a durability
  claim was tested rather than trusted
- [Why a Kyverno policy rolls Pods on ConfigMap changes](configmap-autoreload.md)
- [Why the rule linter alerts on change, not on count](pint-rule-linting.md)
- [Postgres fleet upgrade plan](../postgres/fleet-upgrade-plan.md)
