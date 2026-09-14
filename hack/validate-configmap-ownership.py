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


# git-tracked files only, so a Kustomization that has not been staged yet is
# invisible here in the same way it is invisible to the other validators.
paths = set()
for manifest in flux_kustomization_manifests():
    for line in run("yq", "-r",
                    'select(.kind == "Kustomization"'
                    ' and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/"))'
                    ' and .spec.suspend != true)'
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

print(f"  distinct ConfigMaps across all Kustomizations: {len(owner)}"
      f", from {len(paths)} Kustomization paths")

# A check that examined nothing is not a passing check, and this one's last
# failure was exactly that: silent, and only visible as a count nobody was
# reading.
if not paths:
    print("  NO KUSTOMIZATIONS FOUND -- discovery is broken")
    sys.exit(1)

clashes = {k: v for k, v in owner.items() if len(v) > 1}
if clashes:
    print("  CLAIMED BY MORE THAN ONE KUSTOMIZATION:")
    for (namespace, name), dirs in sorted(clashes.items()):
        print(f"    {namespace}/{name}")
        for d in sorted(dirs):
            print(f"        {d}")
    sys.exit(1)

print("  no ConfigMap is produced by two Kustomizations")
