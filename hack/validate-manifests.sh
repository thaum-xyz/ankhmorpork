#!/bin/bash

# Validates everything Flux applies, against upstream Kubernetes schemas plus
# the CRD catalog, so custom resources (HelmRelease, ExternalSecret, Cluster,
# ...) are checked rather than skipped.
#
# Two kinds of target are validated, matching how Flux itself treats them:
#   - a directory with a kustomization.yaml is rendered with `kustomize build`
#     and the result validated, which also catches broken patches and
#     references,
#   - a directory without one has its manifests validated in place, because
#     Flux applies every yaml it finds there (base/flux-apps and the
#     jsonnet-generated apps/*/manifests work this way).
#
# Usage: ./hack/validate-manifests.sh [dir...]
# With no arguments every live Flux Kustomization path and every kustomization
# in the repository is checked.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
CACHE_DIR="$WORK_DIR/schemacache"
mkdir -p "$CACHE_DIR"

CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
# CRD definitions themselves have no schema in the upstream set; the custom
# resources they define are still validated via the catalog above.
SKIP=CustomResourceDefinition

# apps/monitoring is still generated from jsonnet and needs a wider refactor
# before it can be validated. Drop this once that is done.
EXCLUDE='^apps/monitoring(/|$)'

validate() {
  kubeconform \
    -schema-location default \
    -schema-location "$CRD_CATALOG" \
    -cache "$CACHE_DIR" \
    -skip "$SKIP" \
    -ignore-filename-pattern 'vendor/.*' \
    -ignore-filename-pattern 'jsonnet/.*' \
    -strict \
    "$@"
}

flux_paths() {
  local query='select(.kind == "Kustomization" and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/"))) | .spec.path'
  while IFS= read -r f; do
    local d
    d="$(dirname "$f")"
    if [ -f "$d/kustomization.yaml" ]; then
      kustomize build "$d" 2>/dev/null | yq "$query" 2>/dev/null
    else
      yq "$query" "$f" 2>/dev/null
    fi
  done < <(git ls-files '*.yaml' | xargs grep -l 'kind: Kustomization' 2>/dev/null) \
    | grep -v '^---$' | grep -v '^null$' | grep -v '^$' | sed 's|^\./||'
}

if [ "$#" -gt 0 ]; then
  # An explicit target is validated even if it is normally excluded.
  targets=$(printf '%s\n' "$@")
else
  targets=$(
    {
      flux_paths
      find apps base core -name kustomization.yaml \
        -not -path '*/vendor/*' -not -path '*/jsonnet/*' -exec dirname {} \;
    } | sort -u | grep -Ev "$EXCLUDE"
  )
  echo "Excluded from validation: apps/monitoring (still jsonnet-generated)"
fi

if [ -z "$targets" ]; then
  echo "Nothing to validate" >&2
  exit 1
fi

total=0
failed=""
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  if [ ! -d "$dir" ]; then
    echo "::error::$dir does not exist"
    failed="$failed $dir"
    continue
  fi
  total=$((total + 1))

  if [ -f "$dir/kustomization.yaml" ]; then
    if ! kustomize build "$dir" >"$WORK_DIR/rendered.yaml" 2>"$WORK_DIR/err"; then
      echo "::error file=$dir/kustomization.yaml::kustomize build failed"
      sed 's/^/    /' "$WORK_DIR/err"
      failed="$failed $dir"
      continue
    fi
    if ! out=$(validate "$WORK_DIR/rendered.yaml" 2>&1); then
      echo "::error file=$dir/kustomization.yaml::schema validation failed"
      echo "$out" | sed "s|$WORK_DIR/rendered.yaml|$dir|" | sed 's/^/    /'
      failed="$failed $dir"
    fi
  else
    if ! out=$(validate "$dir" 2>&1); then
      echo "::error::schema validation failed for $dir"
      echo "$out" | sed 's/^/    /'
      failed="$failed $dir"
    fi
  fi
done <<< "$targets"

if [ -n "$failed" ]; then
  echo
  echo "FAILED:"
  for d in $failed; do echo "  - $d"; done
  exit 1
fi

echo "All $total targets render and validate cleanly."
