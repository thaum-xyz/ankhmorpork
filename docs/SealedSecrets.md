# SealedSecrets master key handling

_Note_: Instructions are based on [SealedSecrets readme](https://github.com/bitnami-labs/sealed-secrets/blob/main/README.md)



## Backup

1. Run `kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >master.key`
2. Copy content of `master.key` file to bitwarden under `SealedSecret master key` entry in `Ankhmorpork` directory.



## Check

1. Mount a temporary ramdisk with `mount -t tmpfs -o size=100m tmpfs /mnt/tmp` or use a directory that is an existing ramdisk.
2. Download `master.key` from bitwarden and save it in directory from previous point. Location is described in a [backup section](##Backup).
3. Pick any `SealedSecret` from git repository. Ex. [`apps/cookbook/manifests/secret.yaml`](apps/cookbook/manifests/secret.yaml)
4. Try unsealing `SealedSecret` with `master.key` by using `cat <Sealed_Secret_Location> | kubeseal --recovery-unseal --recovery-private-key master.key`
5. If command doesn't succeed, key is not valid and backup needs to be performed.



## Recovery

1. Stop sealed secrets controller - `k scale deploy --replicas=0 -n kube-system -l name=sealed-secrets-controller`
2. Download `master.key` following procedure from [check section](##Check)
3. Apply `master.key` to a cluster
4. Start sealed secrets controller - `k scale deploy --replicas=1 -n kube-system -l name=sealed-secrets-controller` 
5. Ensure there is at least one SealedSecret in a cluster
6. Observe logs of the controller