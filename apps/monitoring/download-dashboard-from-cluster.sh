#!/bin/bash

set -eou pipeline

CMS=$(kubectl get cm | grep 'grafana-' | cut -d ' ' -f1)
DIR="dashboards"
mkdir "${DIR}"

for cm in $CMS; do
	kubectl get configmap "$cm" -o json | jq -r 'first(.data[])' > "${DIR}/${cm}.json"
done
