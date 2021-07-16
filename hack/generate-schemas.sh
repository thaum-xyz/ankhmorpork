#!/bin/bash

cd $(git rev-parse --show-toplevel)
DIR=tmp/schemas

mkdir -p $DIR

crds=$(grep 'kind: CustomResourceDefinition' -l -R base/ apps/)

for crd in $crds; do
	filename="$(cat "$crd" | gojsontoyaml -yamltojson | jq -r '.spec.names.kind' | tr '[:upper:]' '[:lower:]').json"
	cat "$crd" | gojsontoyaml -yamltojson | jq -r '.spec.versions[0].schema.openAPIV3Schema' > "$DIR/$filename"

	if [ "$(cat "$DIR/$filename")" == "null" ]; then
		cat "$crd" | gojsontoyaml -yamltojson | jq -r '.spec.validation.openAPIV3Schema' > "$DIR/$filename"
	fi
	if [ "$(cat "$DIR/$filename")" == "null" ]; then
		echo "WARN: Cannot generate schema for $crd"
		rm "$DIR/$filename"
	fi
done
