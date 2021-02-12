#!/bin/bash

# Main purpose of this script is to allow rebooting node which is used as 
# a backend for external-nfs storage class. This operation is disruptive
# to some workloads hosted in cluster.
# Following actions are performed by the script:
# 1. Cordoning and draining node
# 2. Scaling argocd application server to 0 (prevents auto recovery)
# 3. Detecting workloads using external-nfs storage class
# 4. Scaling workloads from #3 to 0
# 5. SSH into node and executing reboot
# 6. Uncordoning node
# 7. Scaling workloads from #4 to 1
# 8. Scaling argocd to 1 to perform further recovery

NODE="hyper01"

kubectl cordon "${NODE}"
kubectl drain "${NODE}" --delete-emptydir-data --ignore-daemonsets

sleep 180  # TODO: convert into proper check to see if all resources were moved

#kubectl scale --replicas=0 deployment -n argocd argocd-application-controller



ssh "${NODE}" reboot

sleep 180  # TODO: convert into proper check to see if node is up and available
# kubectl get nodes | grep hyper01 | grep -v NotReady

kubectl uncordon "${NODE}"

#kubectl scale --replicas=1 deployment -n argocd argocd-application-controller
