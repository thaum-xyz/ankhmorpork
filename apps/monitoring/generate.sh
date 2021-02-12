#!/bin/bash

set -euo pipefail

# Install dependencies
if [ ! -d 'jsonnet/vendor' ]; then
  cd jsonnet
  jb install
  cd ../
fi

# Remove old manifests
rm -rf manifests || :

# Generate manifests
jsonnet -J jsonnet/vendor -c -m manifests -S jsonnet/main.jsonnet

# Next step is just an eye-candy and only beautifies yaml files
for i in $(find manifests/ -name *.yaml); do
  mv "$i" "$i.bak"
  yamlfmt < "$i.bak" > "$i"
  rm "$i.bak"
done

# Copy ConfigMapSecrets
for i in configmapsecrets/*.yaml; do
  f="$(basename "$i" | sed 's/-/\//')"
  cp "$i" "manifests/$f"
done
