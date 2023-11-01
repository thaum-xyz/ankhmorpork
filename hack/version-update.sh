#!/bin/bash

set -eo pipefail

get_latest_version() {
    echo >&2 "Checking release version for ${1}"
    curl --retry 5 --silent --fail -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/${1}/releases/latest" 2>/dev/null | jq '.tag_name' | tr -d '"v'
}

CHANGELOG="$(git rev-parse --show-toplevel)/.version-changelog"
DIRECTORY="${1}"

# Scan for files with `application-version-from-github:` comment
FILES=$(grep --exclude=*./vendor/ -rl "$DIRECTORY" -e "application-version-from-github:")

# Test connection to GitHub
echo "Checking connection with GitHub. Expecting a design quote..."
curl --retry 5 --silent --fail -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/zen" 2>/dev/null

# Iterate over each file searching for mark
for f in $FILES; do

    REPOS=$(grep application-version-from-github: "$f" | rev | cut -d: -f1 | xargs | rev)

    for r in $REPOS; do
        LATEST="$(get_latest_version "$r")"
        CURRENT=$(grep "application-version-from-github:.*${r}$" "$f" | cut -d: -f2 | cut -d# -f1 | sed -e 's/[^0-9a-z.-]//g')

        if [ "$LATEST" == "" ] || [ "$LATEST" == "null" ]; then
            echo "Latest version detection failed"
            exit 1
        fi

        echo >&2 "Current: '$CURRENT', Latest: '$LATEST'"
        if [ "$CURRENT" == "$LATEST" ]; then
            echo >&2 "Nothing to do for $r"
            continue
        fi

        # Change only lines with correct metadata
        sed -Ei.bak "s|^(.*)${CURRENT}(.*application-version-from-github:.*${r}.*)$|\1${LATEST}\2|g" "$f"
        sed -Ei.bak "s|^(.*)${CURRENT}(.*application-image-from-github:.*${r}.*)$|\1${LATEST}\2|g" "$f" || echo "No image update for $r due to incorrect or lack of metadata"
        rm *.bak

        # Add to changelog
        echo "$r from $CURRENT to $LATEST" >> "${CHANGELOG}"
    done
done
