#!/bin/bash

COREFILE="$1"

if [ ! -f "$COREFILE" ]; then
	echo "Corefile cannot be found. Please rerun with $0 <Corefile Path>"
	exit 1
fi

set -euo pipefail

HEAD=$(sed '/### local ingress START ###/q' "$COREFILE")
TAIL=$(sed -n '/### local ingress END ###/,$p' "$COREFILE")

cat << EOF > "$COREFILE"
$HEAD
$(kubectl get Ingress -A -o json | jq -r '.items[] | "\(.status.loadBalancer.ingress[0].ip) \(.spec.rules[0].host)"' | sed 's/^/    /g')
$TAIL
EOF
