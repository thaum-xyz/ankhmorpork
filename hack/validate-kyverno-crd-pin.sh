#!/bin/bash

# Checks that the kyverno controllers never get ahead of the policies.kyverno.io
# CRDs they were built against.
#
# The two come from two Flux objects: k8s/crds/ installs the CRDs through the
# kyverno-policy-crds wrapper, whose version is the kyverno-api version it
# wraps, and the kyverno release installs the controllers and drops those same
# CRDs from its manifest with a post-renderer. The check is directional. CRDs
# ahead of the controllers is the safe direction -- schema changes are
# additive, and a field the controller does not know is one it ignores -- and
# Renovate lands crds-layer bumps first on purpose. Controllers ahead of the
# CRDs is the quiet failure: a field the API server prunes is one the
# controller expected, and nothing reports it.
#
# Both charts' dependency lists are the authority, so this asks them rather
# than keeping a copy of the number anywhere.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

CONTROLLERS=k8s/platform/security/kyverno/controllers/release.yaml
CRDS=k8s/crds/kyverno/release.yaml
CRDS_REPOSITORY=k8s/crds/kyverno/repository.yaml

kyverno_version="$(yq '.spec.chart.spec.version' "$CONTROLLERS")"
kyverno_repo="$(yq 'select(.kind == "HelmRepository") | .spec.url' \
  k8s/platform/security/kyverno/controllers/repository.yaml)"

wrapper="$(yq '.spec.chart.spec.chart' "$CRDS")"
wrapper_version="$(yq '.spec.chart.spec.version' "$CRDS")"
wrapper_registry="$(yq 'select(.kind == "HelmRepository") | .spec.url' "$CRDS_REPOSITORY")"

dependency='.dependencies[] | select(.name == "kyverno-api") | .version'

expected="$(helm show chart kyverno --repo "$kyverno_repo" --version "$kyverno_version" \
  | yq "$dependency")"
if [[ -z "$expected" || "$expected" == "null" ]]; then
  echo "kyverno $kyverno_version does not depend on kyverno-api any more." >&2
  echo "If upstream folded the CRDs back in, $CRDS and the post-renderer in" >&2
  echo "$CONTROLLERS both need revisiting." >&2
  exit 1
fi

provided="$(helm show chart "$wrapper_registry/$wrapper" --version "$wrapper_version" \
  | yq "$dependency")"
if [[ -z "$provided" || "$provided" == "null" ]]; then
  echo "$wrapper $wrapper_version does not depend on kyverno-api." >&2
  exit 1
fi

# The newer of two versions. `sort -V` gets everything right except that it
# puts a release before its own prereleases, where semver puts it after.
newer() {
  local a="$1" b="$2"
  if [[ "${a%%-*}" == "${b%%-*}" ]]; then
    [[ "$a" != *-* ]] && { echo "$a"; return; }
    [[ "$b" != *-* ]] && { echo "$b"; return; }
  fi
  printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1
}

if [[ "$provided" == "$expected" ]]; then
  echo "$wrapper $wrapper_version provides kyverno-api $provided, exactly what kyverno $kyverno_version depends on."
elif [[ "$(newer "$provided" "$expected")" == "$provided" ]]; then
  echo "$wrapper $wrapper_version provides kyverno-api $provided, ahead of the $expected kyverno $kyverno_version depends on: the safe direction."
else
  echo "kyverno $kyverno_version expects CRDs newer than the crds layer provides." >&2
  echo "  kyverno $kyverno_version depends on kyverno-api: $expected" >&2
  echo "  $wrapper $wrapper_version provides:            $provided" >&2
  echo >&2
  echo "Controllers ahead of their CRDs fail quietly. Let the $wrapper bump land" >&2
  echo "first -- Renovate opens it in thaum-xyz/helm-charts and then here -- and" >&2
  echo "rebase this." >&2
  exit 1
fi
