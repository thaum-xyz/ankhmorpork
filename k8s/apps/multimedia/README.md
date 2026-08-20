## Caveats

### plex

- traffic policy needs to be "Local" to prevent incorrect assumption of client source IP in plex 
- `ADVERTISE_IP` is tied to LB Service IP

### Storage

- volumes for downloaded torrents, movies, and tv shows are provisioned manually using NFS storage and direct link to bonded interfaces
- in the future mount options for manually provisioned NFS volumes may change. It is worth checking following config:
```
spec:
  ...
  mountOptions:
  - hard
  - nfsvers=4.2
```
