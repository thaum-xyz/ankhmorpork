#!/bin/bash

if ! command -v kubeseal &>/dev/null; then
	echo "kubeseal cannot be found. Exiting."
	exit 1
fi

NAME=""
NAMESPACE=""
read -p "Namespace:   " NAMESPACE
read -p "Secret name: " NAME

CONTINUE="y"
while [[ "$CONTINUE" =~ [yY] ]]; do
	VALUE=""
	read -p "Unencrypted value: " VALUE
	echo -en "$VALUE" | kubeseal --raw --from-file=/dev/stdin --namespace "$NAMESPACE" --name "$NAME"
	echo
	read -p "Continue? " CONTINUE
done

