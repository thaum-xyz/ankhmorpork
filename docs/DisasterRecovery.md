# Disaster Recovery


## Cluster bootstrap

1. Configure nodes and start a cluster using ansible playbooks from `ansible/` directory

2. Recover SealedSecret master key following [SealedSecrets SOP](https://github.com/thaum-xyz/ankhmorpork/blob/master/docs/SealedSecrets.md)

3. Start kubernetes infrastructure using manifests from `base/` subdirectories

   _Note_: some custom resources may not be applied at this stage. Try applying the same configs second time to ensure necessary CR objects are applied

   ```bash
   cd base
   k apply -Rf kube-system/
   for i in $(ls); do kubectl create namespace $i && kubectl apply -Rf $i; done
   sleep 30s
   for i in $(ls); do kubectl create namespace $i && kubectl apply -Rf $i; done
   ```

4. Previous point should start `flux` which should also start managing a cluster and start all applications from `apps/` .

5. Start [recovering PVs](##PersistentVolume Data Recovery)


## PersistentVolume Data Recovery

### managed-nfs-storage StorageClass

Store for managed-nfs-storage is periodically backed up as a whole to a backblaze B2 bucket b2:ankhmorpork-thaum-xyz:/nfs-managed with encryption handled by restic.
The process of mapping restored PVCs to old PV names is not automated and needs to be performed manually by one of two methods:

1. Creating PVs manually and changing `claimRef` to match restored PVCs.
2. Stopping application using PV and moving data from old directories to new ones.

### local-path StorageClass

There is no global method for backing up this storage type. Each application deployment uses its own method of backing up data.

Recommended way is to periodically backup data to a PV in `managed-nfs-storage` and use it as a backup proxy.

## MySQL root password recovery

1. Copy data into local machine
2. `docker run -it -u mysql --entrypoint bash --volume $(pwd)/db:/var/lib/mysql mariadb:10.4.12`
3. `mysqld_safe --skip-grant-tables &`
4. 