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
and the reasoning behind conventions that otherwise look arbitrary. Some of it
is only in commit messages, per-app READMEs and
`.claude/skills/app-deployment/SKILL.md`. Pages still to write are tracked as
[issues labelled `documentation`](https://github.com/thaum-xyz/ankhmorpork/issues?q=is%3Aissue+is%3Aopen+label%3Adocumentation).

## Available now

- [Why Helm values live in a file](helm-values.md) — what inline `spec.values`
  would cost, and why the ConfigMap name is deliberately stable
- [Why observability is split by role](observability-split.md) — the stores are a
  datalake meant for more sources than this cluster, which is the seam
- [How Flux is layered](flux-layering.md) — bootstrap, platform, apps, and why
  reconciling in the wrong order reports success
- [Why storage is split the way it is](storage-durability.md) — and how a durability
  claim was tested rather than trusted
- [Why a Kyverno policy rolls Pods on ConfigMap changes](configmap-autoreload.md)
- [Why the rule linter alerts on change, not on count](pint-rule-linting.md)
- [The Postgres fleet upgrade](postgres-fleet-upgrade.md) — a record: why the fleet
  was scattered, and the two traps that decided the order
- [How a node reboot is gated](node-reboots.md) — what has to agree before a node
  goes down, and why a shorter drain timeout is the safer one
- [Why a database failover interrupts an app](database-failover.md) — the
  no-endpoint moment every `-rw` Service passes through, and why a pooler does
  not cover it
