#!/bin/bash

# Extracts the .spec of every PrometheusRule into tmp/rules/ so pint can lint it.
#
# Selection is by document kind, not by grepping for the string "PrometheusRule":
# that also matched Helm values which merely name the kind (piraeus-datastore's
# driftDetection.ignore), and feeding a HelmRelease spec to pint is a hard error.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

rm -rf tmp/rules
mkdir -p tmp/rules

while IFS= read -r f; do
	yq ea 'select(.kind == "PrometheusRule") | .kind' "$f" 2>/dev/null | grep -q . || continue
	tmpfile="$(echo "$f" | sed 's/\//-/g')"
	yq ea 'select(.kind == "PrometheusRule") | .spec' "$f" > "tmp/rules/$tmpfile"
	echo "Unpacked $f to tmp/rules/$tmpfile"
done < <(git ls-files '*.yaml')
