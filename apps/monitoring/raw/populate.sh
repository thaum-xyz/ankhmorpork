#!/bin/bash

set -euo pipefail

mkdir -p manifests/slos

# Copy raw manifests
for i in raw/*.yaml; do
  f="$(basename "$i" | sed 's/-/\//')"
  cp "$i" "manifests/$f"
done
