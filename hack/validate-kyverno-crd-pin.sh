#!/bin/bash

# Checks that the kyverno-policy-crds chart the crds layer installs wraps the
# same kyverno-api version the kyverno chart depends on.
#
# The two are one upstream release split across two Flux objects: k8s/crds/
# installs the policies.kyverno.io CRDs so that a cold start retries against a
# CRD-only release, and the kyverno release drops those same CRDs from its own
# manifest with a post-renderer. Nothing in either file records that they have
# to move together, and the failure is quiet -- controllers serving one schema
# while the API server advertises another.
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

pinned="$(helm show chart "$wrapper_registry/$wrapper" --version "$wrapper_version" \
  | yq "$dependency")"
if [[ -z "$pinned" || "$pinned" == "null" ]]; then
  echo "$wrapper $wrapper_version does not depend on kyverno-api." >&2
  exit 1
fi

if [[ "$pinned" != "$expected" ]]; then
  echo "The kyverno-api behind $wrapper does not match the kyverno chart's dependency." >&2
  echo "  $wrapper $wrapper_version wraps:        $pinned" >&2
  echo "  kyverno $kyverno_version depends on: $expected" >&2
  echo >&2
  echo "These are one upstream release. Release a $wrapper that wraps $expected" >&2
  echo "from thaum-xyz/helm-charts, then pin that version in $CRDS." >&2
  exit 1
fi

echo "$wrapper $wrapper_version wraps kyverno-api $pinned, the dependency of kyverno $kyverno_version."
