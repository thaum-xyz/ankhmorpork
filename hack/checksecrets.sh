#!/bin/bash

# Go to top-level
cd "$(git rev-parse --show-toplevel)"

EXCLUDES=$( cat <<EOM
apps/monitoring/manifests/grafana/dashboardDatasources.yaml
apps/monitoring/manifests/prometheus/windowsConfig.yaml
EOM
)



FAIL="[ \e[1m\e[31mFAIL\e[0m ]"
SKIP="[ \e[1m\e[33mSKIP\e[0m ]"
OK="[  \e[1m\e[32mOK\e[0m  ]"

LEAKS=""

for file in $(find apps/ base/ -name *.yaml -exec grep -E 'kind:[[:space:]]*Secret' -l {} \;); do
	skip="false"
	for exclude in ${EXCLUDES}; do
                if [ "${file}" == "${exclude}" ]; then
			echo -e "$SKIP Skipping validation on $exclude"
			skip="true"
                        continue
                fi
        done
        if [ "$skip" == "true" ]; then
        	continue
        fi

	new=$(gojsontoyaml -yamltojson < "$file" | jq -cr '..| .data?, .stringData? | select(type != "null")')
	if [ "$new" != "" ]; then
		LEAKS="${file} ${LEAKS}"
	fi
done

if [ "$LEAKS" != "" ]; then
	for file in ${LEAKS}; do
		echo -e "$FAIL File with possible data leak: ${file}"
	done
	exit 1
fi

echo -e "$OK No data found in Secret objects."
exit 0
