#!/bin/bash

# Checks that every live Flux Kustomization spec.path points at a directory
# tracked in git. A typo'd or stale path makes Flux fail to reconcile and
# silently stops deploying whatever depended on it.
#
# A Kustomization is "live" if Flux would actually apply it, which is true when
# either:
#   a) its directory has no kustomization.yaml, so Flux applies every yaml in it
#      directly (this is how base/flux-apps works), or
#   b) it survives `kustomize build` of its directory.
# That distinction matters: a file commented out of a kustomization.yaml is not
# applied, so a stale path in it must not fail this check.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# @tsv, not `+ "\t" +`: yq emits that as a literal backslash-t, which left every
# line unsplittable and silently reduced this whole check to a no-op.
QUERY='select(.kind == "Kustomization" and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/")))
       | [.metadata.name, .spec.path] | @tsv'

# Collect live Kustomizations, one "name<TAB>path" per line.
: > "$WORK_DIR/live.tsv"
while IFS= read -r f; do
  dir="$(dirname "$f")"
  if [ -f "$dir/kustomization.yaml" ]; then
    kustomize build "$dir" 2>/dev/null | yq "$QUERY" 2>/dev/null
  else
    yq "$QUERY" "$f" 2>/dev/null
  fi
done < <(git ls-files '*.yaml' | xargs grep -l 'kind: Kustomization' 2>/dev/null) \
  | grep -v '^---$' | grep -v '^$' | sort -u > "$WORK_DIR/live.tsv"

missing=0
checked=0
while IFS=$'\t' read -r name path; do
  [ -z "${name:-}" ] && continue
  [ -z "${path:-}" ] && continue
  [ "$path" = "null" ] && continue
  checked=$((checked + 1))
  dir="${path#./}"
  # Flux resolves spec.path against the git source, so it must be tracked.
  if [ -z "$(git ls-files "$dir")" ]; then
    echo "::error::Flux Kustomization '$name' points at '$path', which is not tracked in git"
    missing=$((missing + 1))
  fi
done < "$WORK_DIR/live.tsv"

if [ "$missing" -ne 0 ]; then
  echo "$missing of $checked live Flux Kustomization paths are missing"
  exit 1
fi

echo "All $checked live Flux Kustomization paths exist."
