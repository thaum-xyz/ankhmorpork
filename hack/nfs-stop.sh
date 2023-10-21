#!/bin/bash

# WARNING: THIS SCRIPT CAUSES OUTAGE!
# Script is meant to be used when NFS server needs a reboot (usually for firmware update).

# Script excludes PVs with `backup` in their PVC name

# Script stops all resources which use NFS storage. It does it by:
#   1. Scaling down fluxcd replication controllers to prevent automated recovery
#   2. Looking for PVCs using particular storage class
#   3. Scaling down resources using PVCs from #2

# Disable flux
kubectl scale deploy -n flux-system --replicas=0 --all

# Iterate over all namespaces
for ns in $(kubectl get ns -o=jsonpath='{.items[*].metadata.name}'); do

	# Find PVCs
	pvcs=$(kubectl get pvc --namespace $ns -o=jsonpath='{range .items[?(@.spec.storageClassName=="qnap-nfs")]}{.metadata.name}{"\n"}{end}')
	if [ "$pvcs" == "" ]; then
		continue
	fi

	# Exlude backup PVCs
	pvcs=$(echo $pvcs | tr " " "\n" | grep -v "backup" | tr "\n" " ")

	# Find Pods
	pods=""
	for pvc in $pvcs; do
		pods="${pods} $(kubectl describe pvc -n $ns $pvc | sed -n '/Used By/,/Events/p' | grep -v Events | grep -v "<none>" | sed 's/Used By://;s/ //g')"
	done

	# deduplicate
	pods=$(echo $pods | tr " " "\n" | sort -n | uniq)

	# Find controlers
	controlers=""
	for pod in $pods; do
		ctrl=$(kubectl describe pod -n $ns $pod | grep "Controlled By" | cut -d' ' -f4)
		if [[ "$ctrl" =~ "ReplicaSet" ]]; then
			ctrl=$(kubectl describe -n $ns $ctrl | grep "Controlled By" | cut -d' ' -f4)
		fi
		controlers="$controlers $ctrl"
	done

	# deduplicate
	controlers=$(echo $controlers | tr " " "\n" | sort -n | uniq)

	for c in $controlers; do
		kubectl scale --replicas=0 --namespace $ns $c
	done
done

cat <<EOF
Finished scaling down resources which use NFS storage backend.
To trigger automatic recovery scale up flux deployments with following command:

  kubectl scale deploy -n flux-system --replicas=1 --all
EOF
