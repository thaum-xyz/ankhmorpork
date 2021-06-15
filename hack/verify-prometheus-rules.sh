#!/bin/bash

set -euo pipefail

mkdir -p tmp/rules

for f in $(grep -ir --include=*.yaml "PrometheusRule" . | grep kind | grep -v CustomResourceDefinition | sed 's/:.*//'); do
	echo "Checking $f"
	tmpfile="$(echo "$f" | sed 's/\//-/g' | sed 's/.-//').json"
	gojsontoyaml -yamltojson < "$f" | jq .spec > "tmp/rules/$tmpfile";
	( cd tmp/rules && promtool check rules "$tmpfile")

done

ISSUES=0
for f in $(grep -ir --include=*.yaml "PrometheusRule" . | grep kind | grep -v CustomResourceDefinition | sed 's/:.*//'); do
	echo "Checking best practices in $f. Issues detected in:"
	# Validate best practices
	# Get rules without summary or description annotation

	# TODO: enable when all rules use correct annotations
	#cat "$f" | gojsontoyaml -yamltojson | jq '.spec.groups[].rules[] | select(.["alert"]) | select(.annotations.description and .annotations.summary | not)' && ISSUES=1 || :
	cat "$f" | gojsontoyaml -yamltojson | jq -e '.spec.groups[].rules[] | select(.["alert"]) | select([.labels.severity] | inside(["warning", "critical", "info", "none"]) | not)' && ISSUES=1 || :
done
exit $ISSUES
