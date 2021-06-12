# Node Groups

Brief explanation of various node groups available in cluster and conventions to use those groups



## CPU Architecture

Cluster uses two CPU Architectures: amd64 and arm64. This is reflected in by a value of label `kubernetes.io/arch`. Possible values are:

- `kubernetes.io/arch: amd64`
- `kubernetes.io/arch: arm64`



## Networking

Due to architecture limitation of SBCs not all hosts have the same network capabilities. To reflect this, label `network.infra/type` is used. Possible values are:

- `network.infra/type: slow` - default value assigned to nodes, host is limited to ~300Mbps
- `network.infra/type: fast` - high-speed network with 1Gbps connectivity (or higher)

All network cards operate in full duplex mode.



## Storage

Storage is divided into categories described in detail in [Storage.md document](Storage.md). To define which node is hosting what storage types following labels are used:

- `storage.infra/local: true` - node have additional drive dedicated to local storage.

- `storage.infra/main: true` - node is hosting NFS storage

  

## GPU

In addition to labels mentioned above, some nodes may be labeled with `gpu.intel.com/i915` or `gpu.infra/nvidia` labels. It's use is not recommended and if there is a need to use GPU card, it should be used via `resources` field as in following example:

```yaml
resources:
  limits:
    # gpu.intel.com/i915: 1
    nvidia.com/gpu: 1
```

