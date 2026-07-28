#!/bin/bash

set -euo pipefail

mkdir -p tmp/rules

for f in $(grep -ir --include=*.yaml "PrometheusRule" . | grep kind | grep -v CustomResourceDefinition | sed 's/:.*//'); do
	tmpfile="$(echo "$f" | sed 's/\//-/g' | sed 's/.-//')"
	gojsontoyaml -yamltojson < "$f" | jq .spec | gojsontoyaml > "tmp/rules/$tmpfile";
	echo "Unpacked $f to tmp/rules/$tmpfile"
done
