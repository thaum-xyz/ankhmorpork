#!/bin/bash

set -eo pipefail

get_latest_version() {
    echo >&2 "Checking release version for ${1}"
    curl --retry 5 --silent --fail -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/${1}/releases/latest" | jq '.tag_name' | tr -d '"v'
}

DIRECTORY="${1}"

# Scan for files with `version-updater-repo` comment
FILES=$(grep --exclude=*./vendor/ -rl "$DIRECTORY" -e "github-repository:")

# Iterate over each file searching for mark
for f in $FILES; do
    REPOS=$(grep github-repository "$f" | rev | cut -d: -f1 | xargs | rev)
    # Deduplicate
    REPOS=$(echo "${REPOS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    for r in $REPOS; do
        LATEST="$(get_latest_version "$r")"
        CURRENT=$(grep 'version:' "$f" | cut -d: -f2 | cut -d# -f1 | xargs)

        if [ "$LATEST" == "" ]; then
            echo "Latest version detection failed"
            exit 1
        fi

        echo >&2 "Current: $CURRENT, Latest: $LATEST"
        if [ "$CURRENT" == "$LATEST" ]; then
            echo >&2 "Nothing to do for $r"
            continue
        fi
        sed -i "s/$CURRENT/$LATEST/g" "$f"
    done
done

