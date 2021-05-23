#!/bin/bash

set -eo pipefail

# Test only for homer for now
FILE=apps/homer/jsonnet/settings.yaml

get_latest_version() {
  echo >&2 "Checking release version for ${1}"
  curl --retry 5 --silent --fail -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/${1}/releases/latest" | jq '.tag_name' | tr -d '"v'
}

REPO=$(grep version-updater-repo "$FILE" | rev | cut -d: -f1 | xargs | rev)

LATEST="$(get_latest_version "$REPO")"
CURRENT=$(grep 'version:' "$FILE" | cut -d\" -f2)

if [ "$LATEST" == "" ]; then
    echo "Latest version detection failed"
    exit 1
fi

echo "Current: $CURRENT, Latest: $LATEST"
if [ "$CURRENT" == "$LATEST" ]; then
    echo "Nothing to do"
    exit 0
fi
sed -i "s/$CURRENT/$LATEST/g" "$FILE"
