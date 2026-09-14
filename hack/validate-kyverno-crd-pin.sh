#!/bin/bash

# Checks that the kyverno-api HelmRelease in the crds layer pins the same chart
# version the kyverno chart depends on.
#
# The two are one upstream release split across two Flux objects: k8s/crds/
# installs the policies.kyverno.io CRDs so both domains that declare a kyverno
# policy are ordered behind them, and the kyverno release drops those same CRDs
# from its own manifest with a post-renderer. Nothing in either file records
# that they have to move together, and the failure is quiet -- controllers
# serving one schema while the API server advertises another.
#
# The kyverno chart's dependency list is the authority, so this asks it rather
# than keeping a third copy of the number.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

CONTROLLERS=k8s/platform/security/kyverno/controllers/release.yaml
CRDS=k8s/crds/kyverno/release.yaml

kyverno_version="$(yq '.spec.chart.spec.version' "$CONTROLLERS")"
kyverno_repo="$(yq 'select(.kind == "HelmRepository") | .spec.url' \
  k8s/platform/security/kyverno/controllers/repository.yaml)"
pinned="$(yq '.spec.chart.spec.version' "$CRDS")"

expected="$(helm show chart kyverno --repo "$kyverno_repo" --version "$kyverno_version" \
  | yq '.dependencies[] | select(.name == "kyverno-api") | .version')"

if [[ -z "$expected" || "$expected" == "null" ]]; then
  echo "kyverno $kyverno_version does not depend on kyverno-api any more." >&2
  echo "If upstream folded the CRDs back in, $CRDS and the post-renderer in" >&2
  echo "$CONTROLLERS both need revisiting." >&2
  exit 1
fi

if [[ "$pinned" != "$expected" ]]; then
  echo "kyverno-api pin does not match the kyverno chart's dependency." >&2
  echo "  $CRDS pins:                   $pinned" >&2
  echo "  kyverno $kyverno_version depends on: $expected" >&2
  echo >&2
  echo "These are one upstream release. Bump them together." >&2
  exit 1
fi

echo "kyverno-api $pinned matches the dependency of kyverno $kyverno_version."
