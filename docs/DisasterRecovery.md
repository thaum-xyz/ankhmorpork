# Disaster Recovery


## Cluster bootstrap

1. Startup vanilla cluster without ANYTHING from `base/` or `apps/` directories
2. Get SealedSecrets master key from bitwarden and apply it to cluster as described
[here](https://github.com/bitnami-labs/sealed-secrets#how-can-i-do-a-backup-of-my-sealedsecrets) with:
```
$ kubectl apply -f master.key
$ kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```

## Data Recovery

Currently backup recovery is a manual process for each PV. All backups are stored in B2 with keys in bitwarden.

TODO: Describe procedure

## MySQL root password recovery

1. Copy data into local machine
2. `docker run -it -u mysql --entrypoint bash --volume $(pwd)/db:/var/lib/mysql mariadb:10.4.12`
3. `mysqld_safe --skip-grant-tables &`
4. 
