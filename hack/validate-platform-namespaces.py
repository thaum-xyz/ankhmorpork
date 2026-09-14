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
# ESCAPE HATCH: EXEMPT_TARGET below, and it is the only one. It names components
# whose WORKLOAD cannot leave the namespace it targets -- cilium is the CNI and
# has to be reachable before anything else in kube-system -- not components that
# have not moved yet. The entry says why, because "it broke when I tried" and
# "it can never work" need to be told apart by the next person to read this.
#
# device-plugins used to be listed here and was not entitled to be. Its reason
# read "registration is node-local; conventionally a kube-system object" -- the
# first half is the argument for moving it, and the second half is habit. It has
# no ServiceAccount, no RBAC, and nothing outside it names its namespace; the
# kubelet finds it through a host socket. An exemption has to say what breaks,
# not where the object usually sits.

import json
import os
import pathlib
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

# There is deliberately no second escape hatch for a component that renders into
# two namespaces. The one that did was k8s/platform/cluster/flux-system, which
# shipped the flux-system Namespace and the identity everything in it
# impersonated; that namespace was retired when the last app Kustomization moved
# into its own, and nothing has spanned two since. A component that needs to is
# not an exception to record -- it is a component in the wrong place.

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

# Every Flux Kustomization manifest tracked in git, found by the API version it
# declares rather than by where it sits. Globbing directories is what made this
# check go quiet: it read k8s/flux/*, and when that tree was deleted and the app
# Kustomizations moved to k8s/namespaces/<app>/sync.yaml it went on passing over
# most of what it used to cover. Re-globbing the new directories fixes today and
# breaks the next time; this repo has moved that layout three times in a
# fortnight.
def flux_kustomization_manifests():
    tracked = run("git", "ls-files", "k8s/*.yaml", "k8s/**/*.yaml").split()
    return [f for f in tracked
            if "kustomize.toolkit.fluxcd.io/v1" in pathlib.Path(f).read_text()]

# git-tracked only, matching the other validators: a component that has not been
# staged is invisible here exactly as it is to `make validate`.
paths = set()
for manifest in flux_kustomization_manifests():
    for line in run("yq", "-r",
                    'select(.kind == "Kustomization"'
                    ' and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/")))'
                    ' | .spec.path',
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

        if found != domain_ns:
            problems.append((path, domain_ns, found, kind, name))

print(f"  platform components checked: {checked}"
      f" ({len(EXEMPT_TARGET)} exempt target)")

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
    print("  Move it, or add it to EXEMPT_TARGET here with the reason its\n  workload cannot leave the namespace it targets.")
    sys.exit(1)

print("  every platform component renders into its domain namespace")
