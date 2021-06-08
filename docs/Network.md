# Network IP range assignment

_Note: This is under constant development_

Base network in /24 subnet

### .0 - .10

RESTRICTED for network equipment

### .11 - .29

FREE

### .30 - .39

k3s

### .40 - .49

Hypervisors and x86 nodes

### .50 - .54

Static IP allocation in DHCP. MAC addr following pattern: DE:AD:BE:EF:00:xy, ex.
MAC DE:AD:BE:EF:00:50 gets IP ending with .50
MAC DE:AD:BE:EF:00:51 gets IP ending with .51
and so on

### .55 - .79

FREE

### .80 - .89

IPMI and node management (TODO: move to separate VLAN)

### .90 - .99

k8s Loadbalancer pool

### .100 - .254

DHCP pool (TODO: move to separate VLAN)
