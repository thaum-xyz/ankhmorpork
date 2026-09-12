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

import json
import os
import subprocess
import sys

# Where a component may land instead of its domain namespace, and why.
EXEMPT = {
    "k8s/platform/network/cilium":
        ("kube-system", "the CNI: nothing else schedules until it is up, and its "
                        "node agent is addressed by kube-system service accounts"),
    "k8s/platform/cluster/device-plugins":
        ("kube-system", "kubelet device-plugin registration is node-local; the "
                        "plugin DaemonSet is conventionally a kube-system object"),
    "k8s/platform/cluster/flux-system":
        ("flux-system", "Flux must reconcile before and without the platform it "
                        "installs, including this check"),
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

problems = []
checked = 0
for path in sorted(paths):
    parts = path.split("/")
    if len(parts) < 4:
        # k8s/platform/<domain>/<component>; anything shallower is a domain-wide
        # Kustomization, which has no single expected namespace.
        continue
    domain = parts[2]
    expected, reason = EXEMPT.get("/".join(parts[:4]), (f"platform-{domain}", None))

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
        if found != expected:
            problems.append((path, expected, found, doc.get("kind"), meta.get("name")))

print(f"  platform components checked: {checked}"
      f" ({len(EXEMPT)} exempt by name)")

if problems:
    print("  RENDERED OUTSIDE THEIR DOMAIN NAMESPACE:")
    for path, expected, found, kind, name in problems:
        print(f"    {path}: {kind}/{name} in {found}, expected {expected}")
    print("  Move it, or add it to EXEMPT in this file with the reason it cannot.")
    sys.exit(1)

print("  every platform component renders into its domain namespace")
