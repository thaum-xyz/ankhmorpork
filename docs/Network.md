# Network IP range assignment

Base network in /24 subnet

### .0 - .10

RESTRICTED for network equipment

### .11 - .19

k8s nodes

### .20 - .29

k8s cluster old loadbalancer pool. Will be added to k8s nodes pool.

### .30 - .38

FREE

### .39

iSCSI virtual IP

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
