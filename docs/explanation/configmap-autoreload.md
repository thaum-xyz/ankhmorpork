# Why a Kyverno policy rolls Pods on ConfigMap changes

A Pod mounting a ConfigMap sees the file change — the kubelet syncs the volume
within a minute — but a process that reads its configuration once at startup
never notices. Nothing in Kubernetes restarts it.

That gap is quiet, and quiet is the problem. Two components here were running
configuration nobody could tell was stale.

## What it cost before

**`pint` ignored its own config for six hours.** A change adding three check
scopes reached the ConfigMap within minutes. `pint` reads `pint.hcl` at startup
and has no reload endpoint, so it went on reporting the six findings those scopes
silence. The Pod template had no checksum annotation and the ConfigMap has a
stable name, so nothing the Deployment referenced had changed and no rollout was
triggered.

**`github-receiver` filed three days of mis-titled issues.** Commit `84b6c1f7`
fixed a template so alerts without a namespace label would stop being titled
`Alert: <name> in <no value>`. It changed only `configmap.yaml`. The Deployment
carried two hand-maintained md5 annotations, which did not move, so no rollout
happened and the running Pod kept formatting titles with the pre-fix template.
The annotation on that Pod matched nothing in the repository.

The second failure is the more interesting one: the mechanism intended to catch
this — a checksum in the Pod template — **depended on a human remembering to
update it**, and silently did nothing when they did not.

## The options, and why this one

### A sidecar that reloads in place

`blackbox-exporter` runs [`configmap-reload`](https://github.com/jimmidyson/configmap-reload),
which watches the mounted directory and hits a webhook. It is the best answer
when it applies: no Pod restart at all.

It needs the process to *have* a reload endpoint. `pint` does not.

### A hash in the ConfigMap name

Kustomize's `configMapGenerator` can append a content hash, which changes the
ConfigMap name, which changes the volume reference, which rolls the Pod. Correct,
and about four lines.

It only covers ConfigMaps that kustomize generates in the same kustomization, and
it cannot help with Secrets at all — those are written at runtime by
external-secrets and never appear in git. Fixing one workload this way leaves the
class intact.

### Watch the ConfigMap, mutate the workload

The obvious shape, and it does not work here. *"When a ConfigMap changes, annotate
the Deployments that use it"* is a **mutate-existing** rule, because an admission
webhook can only mutate **the object being admitted** — and here the admitted
object is the ConfigMap, not the Deployment.

Mutate-existing is executed by Kyverno's background controller, which is
[deliberately disabled](https://github.com/thaum-xyz/ankhmorpork/blob/master/k8s/platform/security/kyverno/controllers/values.yaml)
in this cluster. Enabled anyway, such a rule parks UpdateRequests in Pending
forever — a failure already recorded on `mutate-nfs-pvc-alert-exclusion`.

### Invert the trigger

So the **workload** is the admitted object, and it carries the ConfigMap's
version:

```
ConfigMap changes  ->  its resourceVersion bumps
Flux re-applies    ->  the webhook stamps the new value into the Pod template
                   ->  Pod template changed  ->  rollout
```

This needs no background controller, and no new RBAC: the Kyverno admission
controller already holds `get`/`list`/`watch` on ConfigMaps. It works because
everything here is applied by Flux on an interval — a workload nobody re-applies
would never be stamped.

## What it trades

**Latency instead of immediacy.** A mutate-existing rule would react to the
ConfigMap write. This reacts to the next apply, and in practice to the one after
that: Flux applies the workload before it writes the updated ConfigMap, so the
first reconcile stamps a value that has not changed yet.

```
configmap written by kustomize-controller   05:50:41
deployment written by kustomize-controller  05:43:34   <- skipped this reconcile
pod rolled                                  05:57
```

Up to two intervals — ten minutes at the 5m Kustomization interval. For a linter
config or an issue template that is irrelevant. For something latency-sensitive
it would not be.

**Silence when it does not match.** `failurePolicy: Ignore` is deliberate: the
policy runs on *every* Deployment and StatefulSet admission, including Flux's own,
so a renamed ConfigMap making `resource.Get` error must not be able to block
deploys. Failing open costs a stale Pod; failing closed costs the ability to
deploy at all.

The cost of that choice is that a misplaced opt-in annotation does nothing
visible. That happened immediately — the `github-receiver` fix put the annotation
on the Pod template rather than the workload, and the only symptom was the
absence of a stamp.

## Why not Secrets { #why-not-secrets }

The same policy could watch Secrets, and there is a real gap to close: **69
ExternalSecrets** are reconciled by external-secrets, and a rotation restarts
nothing that consumes them.

It is left out on purpose. `resource.Get` on a Secret requires the Kyverno
admission controller to hold read on **every Secret in the cluster**, which it
does not today. That is a privilege decision worth taking on its own merits
rather than as a side effect of fixing a linter's config reload.

## What to take from this

The durable lesson is not the policy. It is that **a reload mechanism which
depends on someone remembering to update a checksum is not a mechanism**. Both
failures above were invisible: the configuration was correct in git, correct in
the cluster's ConfigMap, and wrong only in the process that had read it minutes
or days earlier — the one place nothing was looking.
