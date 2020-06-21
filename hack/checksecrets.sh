#!/bin/bash

# Go to top-level
cd "$(git rev-parse --show-toplevel)"

LEAKS=""

for file in $(find apps/ base/ -name *.yaml -exec grep -E 'kind:[[:space:]]*Secret' -l {} \;); do
	new=$(gojsontoyaml -yamltojson < "$file" | jq -cr '..| .data?, .stringData? | select(type != "null")')
	if [ "$new" != "" ]; then
		LEAKS="${file}\n${LEAKS}"
	fi
done

if [ "$LEAKS" != "" ]; then
	echo -e "Files with secure data leak:"
	echo -e "${LEAKS}"
	exit 1
fi

echo "No data found in Secret objects."
exit 0
