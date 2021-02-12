#!/bin/bash

set -euo pipefail

# Copy ConfigMapSecrets
for i in configmapsecrets/*.yaml; do
  f="$(basename "$i" | sed 's/-/\//')"
  cp "$i" "manifests/$f"
done
