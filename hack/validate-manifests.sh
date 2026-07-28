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
#     Flux applies every yaml it finds there (base/flux-apps and several
#     apps/*/manifests work this way).
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

validate() {
  kubeconform \
    -schema-location default \
    -schema-location "$CRD_CATALOG" \
    -cache "$CACHE_DIR" \
    -skip "$SKIP" \
    -strict \
    "$@"
}

# Flux APIs that are deprecated upstream and removed in newer Flux versions.
# Everything is on helm.toolkit.fluxcd.io/v2 and source.toolkit.fluxcd.io/v1;
# this stops an old one creeping back in via a copied-and-pasted manifest.
#
# This is a source-level grep rather than kubeconform's -reject because -reject
# matches on kind only, not group/version -- `-reject HelmRelease` would reject
# every HelmRelease regardless of apiVersion, which is not what we want.
#
# image.toolkit.fluxcd.io/v1beta2 is deliberately not listed: that is still the
# current storage version for ImagePolicy and ImageRepository.
DEPRECATED_APIS='^apiVersion: (helm\.toolkit\.fluxcd\.io/v2beta[12]|source\.toolkit\.fluxcd\.io/v1beta[12]|kustomize\.toolkit\.fluxcd\.io/v1beta[12]|notification\.toolkit\.fluxcd\.io/v1beta[12])$'

check_deprecated_apis() {
  local hits
  hits=$(git ls-files '*.yaml' '*.yml' | xargs grep -nE "$DEPRECATED_APIS" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "Deprecated Flux API versions found -- migrate to the GA versions:"
    echo "$hits" | while IFS=: read -r f l rest; do
      echo "::error file=$f,line=$l::deprecated Flux API: ${rest# }"
    done
    return 1
  fi
  echo "No deprecated Flux API versions."
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
  targets=$(printf '%s\n' "$@")
else
  targets=$(
    {
      flux_paths
      find apps base core -name kustomization.yaml -exec dirname {} \;
    } | sort -u
  )
fi

if [ -z "$targets" ]; then
  echo "Nothing to validate" >&2
  exit 1
fi

# Repo-wide policy check; only meaningful on a full run.
api_check=0
if [ "$#" -eq 0 ]; then
  check_deprecated_apis || api_check=1
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

[ "$api_check" -ne 0 ] && exit 1

echo "All $total targets render and validate cleanly."
