#!/usr/bin/env python3

# Fails if a platform component renders namespaced objects outside the
# `platform-<domain>` namespace its directory puts it in --
# k8s/platform/security/* belongs in platform-security, and so on.
#
# The point is not tidiness. A namespace here is the unit three other things
# are keyed to: the flux-reconciler identity Flux impersonates, the group
# RoleBindings generate-group-rolebindings writes, and the blast radius of a
# `prune`. One component per namespace made those three the same question by
# accident. Naming the namespace after the domain makes it a decision, and this
# check is what stops the two drifting apart silently -- a component whose
# kustomization keeps the old `namespace:` renders and validates perfectly.
#
# ESCAPE HATCH: EXEMPT below. Some components genuinely cannot move -- cilium
# is the CNI and has to be reachable before anything else in kube-system, flux
# must reconcile before and without the rest of the platform. Each entry names
# the namespace and why, because "it broke when I tried" and "it can never work"
# need to be told apart by the next person to read this.
#
# device-plugins used to be listed here and was not entitled to be. Its reason
# read "registration is node-local; conventionally a kube-system object" -- the
# first half is the argument for moving it, and the second half is habit. It has
# no ServiceAccount, no RBAC, and nothing outside it names its namespace; the
# kubelet finds it through a host socket. An exemption has to say what breaks,
# not where the object usually sits.

import json
import os
import subprocess
import sys

# A component whose WORKLOAD cannot leave its namespace, but whose Flux objects
# have been consolidated into the domain namespace anyway. The HelmRelease sits
# in platform-<domain> and carries targetNamespace; only that target is exempt,
# and the HelmRepository and values ConfigMap beside it are checked normally.
#
# This is the split worth keeping: the interesting fact is where the workload
# runs, so the check follows targetNamespace rather than being satisfied by the
# custom resource having moved.
EXEMPT_TARGET = {
    "k8s/platform/network/cilium":
        ("kube-system", "the CNI: nothing else schedules until it is up, and its "
                        "node agent is addressed by kube-system service accounts"),
}

# A component that legitimately spans two namespaces: its objects may be in the
# domain namespace OR in the one named here, and nowhere else.
#
# Not the same as "unmoved". flux's controllers DO run in platform-cluster; what
# stays behind is the flux-system namespace object and the flux-reconciler
# identity that every Kustomization impersonates. Those are held there by
# references that are namespace-local, not by inertia, and they leave when the
# Kustomizations do.
ALSO_ALLOWED = {
    "k8s/platform/cluster/flux-system":
        ("flux-system", "the reconciler identity is resolved in the "
                        "Kustomization's own namespace, so it stays with the "
                        "Kustomizations until those move too"),
}

# Cluster-scoped kinds rendered anywhere under k8s/platform. kustomize stamps
# the kustomization's `namespace:` onto these too -- it cannot know the scope of
# a CRD kind -- and the API server ignores it, so they are not evidence of
# anything and are skipped. Unknown kinds are treated as namespaced: a new
# cluster-scoped kind gets flagged once and added here, which is the safe
# direction to be wrong in.
CLUSTER_SCOPED = {
    "CiliumBGPAdvertisement", "CiliumBGPClusterConfig", "CiliumBGPPeerConfig",
    "CiliumLoadBalancerIPPool", "ClusterIssuer", "ClusterRole",
    "ClusterRoleBinding", "ClusterSecretStore", "CustomResourceDefinition",
    "DeletingPolicy", "GeneratingPolicy", "MutatingPolicy", "Namespace",
    "NodeFeatureRule", "StorageClass", "ValidatingPolicy",
}


def run(*cmd, stdin=None):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True).stdout


os.chdir(run("git", "rev-parse", "--show-toplevel").strip())

# git-tracked only, matching the other validators: a component that has not been
# staged is invisible here exactly as it is to `make validate`.
paths = set()
for manifest in run("git", "ls-files", "k8s/flux/platform/*", "k8s/bootstrap/*").split():
    for line in run("yq", "-r",
                    'select(.kind == "Kustomization") | .spec.path',
                    manifest).splitlines():
        line = line.strip().removeprefix("./")
        if line.startswith("k8s/platform/"):
            paths.add(line)

# A domain-wide Kustomization -- k8s/platform/<domain>, three segments -- names no
# single expected namespace, so it used to be skipped. Once one Kustomization
# covers a whole domain that skip is every component, and the check passes having
# examined nothing. Expand it into the components its entrypoint lists instead.
components = set()
for path in sorted(paths):
    if len(path.split("/")) >= 4:
        components.add(path)
        continue
    listed = run("yq", "-r", ".resources[]",
                 f"{path}/kustomization.yaml").split()
    components.update(f"{path}/{r.rstrip('/')}" for r in listed)

problems = []
checked = 0
for path in sorted(components):
    parts = path.split("/")
    domain = parts[2]
    component = "/".join(parts[:4])
    domain_ns = f"platform-{domain}"
    also = ALSO_ALLOWED.get(component, (None, None))[0]

    rendered = run("kustomize", "build", path)
    if not rendered.strip():
        continue
    try:
        docs = json.loads(run("yq", "ea", "-o=json", "[.]", "-", stdin=rendered))
    except json.JSONDecodeError:
        continue

    checked += 1
    for doc in docs:
        if not isinstance(doc, dict) or doc.get("kind") in CLUSTER_SCOPED:
            continue
        meta = doc.get("metadata") or {}
        found = meta.get("namespace")
        name = meta.get("name")
        kind = doc.get("kind")

        spec = doc.get("spec") or {}
        target = spec.get("targetNamespace")

        # A HelmRelease that sets targetNamespace and nothing else is a trap.
        # storageNamespace defaults to the HelmRelease's own namespace and
        # releaseName to "[TargetNamespace-]Name", so a release that was moved
        # this way and later loses either pin does not fail -- Helm simply stops
        # recognising the existing release and installs a second copy beside it.
        # For cilium that is a second CNI. Renders clean, passes kubeconform,
        # and is only visible in `helm list`, so it is asserted here.
        if kind == "HelmRelease" and target:
            for field in ("storageNamespace", "releaseName"):
                if not spec.get(field):
                    problems.append((path, f"{field} to be set (targetNamespace is)",
                                     "unset", kind, name))

        if kind == "HelmRelease" and component in EXEMPT_TARGET and target:
            # Two separate assertions: the object belongs in the domain
            # namespace like any other, and its target is the exempted one.
            allowed = EXEMPT_TARGET[component][0]
            if found != domain_ns:
                problems.append((path, domain_ns, found, kind, name))
            if target != allowed:
                problems.append((path, allowed, target,
                                 kind + " targetNamespace", name))
            continue

        if found != domain_ns and found != also:
            wanted = domain_ns if also is None else f"{domain_ns} or {also}"
            problems.append((path, wanted, found, kind, name))

print(f"  platform components checked: {checked}"
      f" ({len(EXEMPT_TARGET)} exempt target, {len(ALSO_ALLOWED)} spanning two)")

# A check that examined nothing is not a passing check. This one went quiet once
# before, when the per-component Kustomizations it read the component list from
# were replaced by five domain-wide ones.
if not checked:
    print("  NO COMPONENTS EXAMINED -- the component list is being built wrong")
    sys.exit(1)

if problems:
    print("  RENDERED OUTSIDE THEIR DOMAIN NAMESPACE:")
    for path, expected, found, kind, name in problems:
        print(f"    {path}: {kind}/{name} in {found}, expected {expected}")
    print("  Move it, or add it to EXEMPT_TARGET / ALSO_ALLOWED here with the\n  reason it cannot move.")
    sys.exit(1)

print("  every platform component renders into its domain namespace")
