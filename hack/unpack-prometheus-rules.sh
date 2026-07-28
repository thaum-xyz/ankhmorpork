#!/bin/bash

set -euo pipefail

mkdir -p tmp/rules

# apps/monitoring is still generated from jsonnet and is excluded from CI checks
# until it gets refactored. Drop this filter once that is done.
EXCLUDE='^\./apps/monitoring/'

for f in $(grep -ir --include=*.yaml "PrometheusRule" . | grep kind | grep -v CustomResourceDefinition | sed 's/:.*//' | grep -Ev "$EXCLUDE"); do
	tmpfile="$(echo "$f" | sed 's/\//-/g' | sed 's/.-//')"
	gojsontoyaml -yamltojson < "$f" | jq .spec | gojsontoyaml > "tmp/rules/$tmpfile";
	echo "Unpacked $f to tmp/rules/$tmpfile"
done
