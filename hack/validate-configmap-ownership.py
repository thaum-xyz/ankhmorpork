#!/usr/bin/env python3

# Fails if two Flux Kustomizations render a ConfigMap with the same
# namespace/name. Each renders fine alone, so `kustomize build` and kubeconform
# both pass; the conflict only appears once they are applied together, where
# whichever reconciles last silently wins.
#
# This bit once: alloy and kube-prometheus-stack both generated a ConfigMap
# called "values" after alloy moved into platform-observability, and the
# kube-prometheus-stack HelmRelease spent a day being handed alloy's config.
#
# Suspended Kustomizations are skipped. The failure this catches is two
# reconcilers writing the same object, and a suspended one writes nothing, so
# counting it would report a clash that cannot happen. It also makes the check
# usable during a handover, where the object being retired and the one adopting
# it necessarily render the same ConfigMaps until the first is deleted.

import collections
import json
import os
import pathlib
import subprocess
import sys


def run(*cmd, stdin=None):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True).stdout


os.chdir(run("git", "rev-parse", "--show-toplevel").strip())

# git-tracked files only, so a Kustomization that has not been staged yet is
# invisible here in the same way it is invisible to the other validators. Flux
# Kustomizations live in k8s/bootstrap/ (the layers and the platform domains)
# and beside each app's Namespace in k8s/namespaces/<app>/.
manifests = run("git", "ls-files", "k8s/bootstrap/*", "k8s/namespaces/*").split()

paths = set()
for manifest in manifests:
    for line in run("yq", "-r",
                    'select(.kind == "Kustomization" and .spec.suspend != true)'
                    ' | .spec.path',
                    manifest).splitlines():
        line = line.strip()
        if line and line != "null":
            paths.add(line.removeprefix("./"))

owner = collections.defaultdict(set)
for path in sorted(paths):
    if not pathlib.Path(path).is_dir():
        continue
    rendered = run("kustomize", "build", path)
    if not rendered.strip():
        continue
    try:
        docs = json.loads(run("yq", "ea", "-o=json", "[.]", "-", stdin=rendered))
    except json.JSONDecodeError:
        continue
    for doc in docs:
        if not isinstance(doc, dict) or doc.get("kind") != "ConfigMap":
            continue
        meta = doc.get("metadata") or {}
        owner[(meta.get("namespace"), meta.get("name"))].add(path)

print(f"  distinct ConfigMaps across all Kustomizations: {len(owner)}")

clashes = {k: v for k, v in owner.items() if len(v) > 1}
if clashes:
    print("  CLAIMED BY MORE THAN ONE KUSTOMIZATION:")
    for (namespace, name), dirs in sorted(clashes.items()):
        print(f"    {namespace}/{name}")
        for d in sorted(dirs):
            print(f"        {d}")
    sys.exit(1)

print("  no ConfigMap is produced by two Kustomizations")
