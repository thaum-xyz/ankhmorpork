#!/bin/bash

set -euo pipefail

rm -rf manifests || :
jsonnet -c -m manifests -S jsonnet/main.jsonnet

# Next step is just an eye-candy and only beautifies yaml files
cd manifests
for i in *.yaml; do
  mv "$i" "$i.bak"
  yamlfmt < "$i.bak" > "$i"
  rm "$i.bak"
done
