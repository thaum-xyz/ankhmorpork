# Storage

_Note: Document is outdated and needs an update._

Ankhmorpork storage is represented by 3 Kubernetes Storage Classes each with different properties. Such division allows to cover all possible usecases for volume-based storage. Table below presents Storage Classes properties in clear way.

Class      | High Performance | Capacity  | Resiliency
-----------|------------------|-----------|-----------
local-path | YES              | possible  |
NFS        |                  |   YES     |
Longhorn   | possible         |           |  YES

_Note: Ankhmorpork environment currently doesn't host any object storage._

## Available Storage Classes

### local-path

- volume provisioning is realized by [local-path-provisioner](https://github.com/rancher/local-path-provisioner).
- essentially a `hostPath` mount for volumes
- performance is as good as underlying hardware storage
- on node all volumes are stored in `/var/lib/rancher/k3s/storage`.
- can be mounted in RWX and RWO modes

_Note: Volumes are not retained!_

### external-nfs

- volume provisioning is realized by [external-nfs-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- mounted nfs volume from `hyper01` node
- data is not stored on nodes running workload
- underlying storage system is based on ZFS RAIDZ1 pool with 4 HDDs (no SLOG, no L2ARC, dedicated 8GB RAM max)
- data on `hyper01` host is stored in `datastore/nfsshare` zfs pool mounted at `/srv/storage/kubernetes`
- can be mounted in RWX and RWO modes

_Note: Long term network disruption causes Volume disconnection._

### longhorn

- volume provisioning is realized by [longhorn](https://longhorn.io/)
- data is stored on dedicated nodes with replication factor of at least 2
- on dedicated nodes data is stored in `/var/lib/longhorn`
- two ways of mounting volume depending on `accessMode`
  - RWX type is using NFS as mount mechanism
  - RWO type mounts PVs from `/dev/longhorn` and those devices are created by CSI plugin when PV is created.
- snapshotting is supported from web UI
- volumes can be automatically backed up to NFS device

## Hardware considerations

All amd64 nodes are equipped with SATA SSD or NVMe drives used for system partition and possibly for storing data.

All arm64 nodes are equipped with SD cards (class A1 or higher) but they do not have any dedicated storage devices.

`hyper01` is a special host with HDD drives for high capacity.
