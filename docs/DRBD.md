# DRBD

TODO: Cover this in Storage.md

## Network layout

DRBD replication should be over 192.168.40.0/24 network

iSCSI exposed volumes should use 192.168.2.0/24 network (default for k8s cluster)

This split ensures fast replication over dedicated network link (with dedicated HW).
