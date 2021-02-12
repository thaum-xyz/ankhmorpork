#!/bin/bash

set -euo pipefail

mkdir -p tmp/rules

for f in $(grep -ir --include=*.yaml "PrometheusRule" . | grep kind | grep -v CustomResourceDefinition | sed 's/:.*//'); do
    echo "$f"
    tmpfile="$(echo "$f" | sed 's/\//-/g' | sed 's/.-//').json"
    gojsontoyaml -yamltojson < "$f" | jq .spec > "tmp/rules/$tmpfile";
    ( cd tmp/rules && promtool check rules "$tmpfile")
done
