#!/bin/bash

# Fails if two Flux Kustomizations render a ConfigMap with the same
# namespace/name. Each renders fine alone, so `kustomize build` and kubeconform
# both pass; the conflict only appears once they are applied together, where
# whichever reconciles last silently wins.
#
# This bit once: alloy and kube-prometheus-stack both generated a ConfigMap
# called "values" after alloy moved into platform-observability, and the
# kube-prometheus-stack HelmRelease spent a day being handed alloy's config.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 hack/validate-configmap-ownership.py
