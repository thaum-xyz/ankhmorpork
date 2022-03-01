# Storage

Ankhmorpork storage is represented by 2 Kubernetes Storage Classes each with different properties.

Class            | Performance | Capacity  | Data Resiliency | High Availability
-----------------|-------------|-----------|-----------------|-----------
local-path       | YES         | possible  | -               | -
qnap-nfs-storage | -           |   YES     | YES             | -

_Note: Ankhmorpork environment currently doesn't host any object storage._

## Available Storage Classes

### local-path

- volume provisioning is realized by [local-path-provisioner](https://github.com/rancher/local-path-provisioner).
- essentially a `hostPath` mount for volumes
- performance is as good as underlying hardware storage
  - amd64 nodes have dedicated SSD handling this storage type
  - arm64 nodes may have dedicated USB flash drives or SSDs
- on node all volumes are stored in `/var/lib/rancher/k3s/storage`.
- can be mounted in RWX and RWO modes

_Note: Volumes are not retained by default!_

### qnap-nfs-storage

- volume provisioning is realized by [external-nfs-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- mounted nfs volume from dedicated QNAP NAS
- underlying storage system is based on QNAP ZFS RAID5 pool with 4 HDDs
- can be mounted in RWX and RWO modes

_Note: Long term network disruption causes Volume disconnection._

## Hardware considerations

All amd64 nodes are equipped with SATA SSD or NVMe drives used for system partition and possibly for storing data.

All arm64 nodes are equipped with SD cards (class A1 or higher) but they do not always have additional dedicated storage devices.

## Partitioning

### arm64 hosts

To reduce chances of data loss due to SD card failure, some mountpoints are offloaded to RAM or dedicated partitions on
a different medium. Below is a partition layout for a typical host:

PARTITION REF     | MOUNTPOINT       | TYPE  | NOTES
------------------|------------------|-------|---------
LABEL=writable	  | /                | ext4  | SD card
LABEL=system-boot | /boot/firmware   | vfat  | SD card
tmpfs             | /run             | tmpfs | max 10% of RAM
tmpfs             | /tmp             | tmpfs | max 10% of RAM
LABEL=logs        | /var/log         | ext4  | SSD or USB stick
LABEL=rancher     | /var/lib/rancher | ext4  | SSD or USB stick
