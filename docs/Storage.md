# Storage

Note: everything here is in progress and can change

## Available Storage Types

### Capacity (NFS external)

TODO: Consider switching this to ZFS pool with SSD as cache

RAID5 storage based on HDDs. Internally it is bound to LVM volume called "k8s-nfs-capacity" in "storage" VG.
This is an NFS store with  in /srv/storage/kubernetes/capacity
To allow disk spindown and lower power consumption, this class should be used only for applications
with infrequent disk IO.

### Replicated (DRBD + iSCSI)

Essentially RAID1 over lan. Physical disks are located on node01 any hyper01. Replication is happening over dedicated
network (with dedicated HW) on 192.168.40.0/24 subnet. iSCSI is available for all k8s nodes.

TODO: More details

### High-Speed-NFS

Special type available only on node01 and hyper01. This is invisible to k8s and accessible only via `hostPath`. On lower
level those are NFS volumes attached over dedicated network (same one as in #Replicated storage type). 

## K8S storage classes

### external-nfs

Tied to #Capacity storage type

### iscsi (TODO)

Tied to #Replicated storage type
