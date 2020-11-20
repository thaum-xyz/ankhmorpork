#!/bin/bash

# Go to top-level
cd "$(git rev-parse --show-toplevel)"

EXCLUDE="apps/logging/loki/03_config.yaml"

FAIL="[ \e[1m\e[31mFAIL\e[0m ]"
SKIP="[ \e[1m\e[33mSKIP\e[0m ]"
OK="[  \e[1m\e[32mOK\e[0m  ]"

LEAKS=""

for file in $(find apps/ base/ -name *.yaml -exec grep -E 'kind:[[:space:]]*Secret' -l {} \;); do
	if [ "$file" == "$EXCLUDE" ]; then
		echo -e "$SKIP Skipping validation on $EXCLUDE"
		continue
	fi
	new=$(gojsontoyaml -yamltojson < "$file" | jq -cr '..| .data?, .stringData? | select(type != "null")')
	if [ "$new" != "" ]; then
		LEAKS="${file}\n${LEAKS}"
	fi
done

if [ "$LEAKS" != "" ]; then
	echo -e "$FAIL Files with secure data leak:"
	echo -e "$FAIL ${LEAKS}"
	exit 1
fi

echo -e "$OK No data found in Secret objects."
exit 0
