# Storage



Ankhmorpork storage is represented by 2 Kubernetes Storage Classes each with different properties.

Class      | Performance | Capacity  | Data Resiliency | High Availability 
-----------|------------------|-----------|-----------|-----------
local-path | YES              | possible  |-|-
managed-nfs-storage        | - |   YES     |YES|-

_Note: Ankhmorpork environment currently doesn't host any object storage._

## Available Storage Classes

### local-path

- volume provisioning is realized by [local-path-provisioner](https://github.com/rancher/local-path-provisioner).
- essentially a `hostPath` mount for volumes
- performance is as good as underlying hardware storage
  - amd64 nodes have dedicated SSD handling this storage type
  - arm64 nodes may have dedicated USB flash drives
- on node all volumes are stored in `/var/lib/rancher/k3s/storage`.
- can be mounted in RWX and RWO modes

_Note: Volumes are not retained by default!_

### managed-nfs-storage

- volume provisioning is realized by [external-nfs-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- mounted nfs volume from `metal01` node
- data is not stored on nodes running workload
- underlying storage system is based on ZFS RAIDZ1 pool with 4 HDDs (no SLOG, no L2ARC, dedicated 8GB RAM max)
- data on `hyper01` host is stored in `datastore/nfsshare` zfs pool mounted at `/srv/storage/kubernetes`
- can be mounted in RWX and RWO modes

_Note: Long term network disruption causes Volume disconnection._

## Hardware considerations

All amd64 nodes are equipped with SATA SSD or NVMe drives used for system partition and possibly for storing data.

All arm64 nodes are equipped with SD cards (class A1 or higher) but they do not always have additional dedicated storage devices.

`metal01` is a special host with HDD drives for high capacity.
