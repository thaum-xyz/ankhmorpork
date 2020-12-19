# Network IP range assignment

_Note: This is under constant development_

Base network in /24 subnet

### .0 - .10

RESTRICTED for network equipment

### .11 - .29

k8s nodes

### .30 - .39

FREE

### .40 - .49

Hypervisors and x86 nodes

### .50 - .79

FREE

### .80 - .89

IPMI and node management (TODO: move to separate VLAN)

### .90 - .99

k8s Loadbalancer pool

### .100 - .254

DHCP pool (TODO: move to separate VLAN)
