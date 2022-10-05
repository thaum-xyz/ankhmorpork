# LACP

## Netplan

After ubuntu installation LACP on bond interface may not be enabled causing networking issues.

Following configuration creates a bond interface with LACP enabled in netplan:
```
network:
  bonds:
    bond0:
      addresses:
      - 192.168.2.40/24
      gateway4: 192.168.2.1
      nameservers:
        addresses:
        - 192.168.2.1
        - 1.1.1.1
      interfaces:
      - enp35s0
      - enp36s0
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        down-delay: 200
        up-delay: 100
        transmit-hash-policy: layer2
        lacp-rate: fast
 
  ethernets:
    enp1s0f0: {}
    enp1s0f1: {}
    enp35s0: {}
    enp36s0: {}
    enx3ec7ac7ee41d: {}
  version: 2
```

Information taken from https://www.snel.com/support/how-to-set-up-lacp-bonding-on-ubuntu-18-04-with-netplan/
