# LACP

## Netplan

After ubuntu installation LACP on bond interface may not be enabled causing networking issues.

Following configuration creates 2 bond interfaces, each with LACP enabled in netplan:
```
network:
  bonds:
    bond0:
      addresses:
       - 192.168.2.41/24
      gateway4: 192.168.2.1
      interfaces:
      - enp1s0f0
      - enp1s0f1
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        down-delay: 200
        up-delay: 100
        transmit-hash-policy: layer2
        lacp-rate: fast
    bond1:
      addresses:
      - 192.168.40.3/24
      dhcp4-overrides:
        use-routes: false
      interfaces:
      - enp1s0f2
      - enp1s0f3
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        down-delay: 200
        up-delay: 200
        transmit-hash-policy: layer2
        lacp-rate: fast
  ethernets:
    enp1s0f0: {}
    enp1s0f1: {}
    enp1s0f2: {}
    enp1s0f3: {}
    enp3s0:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 600
  version: 2
```

Information taken from https://www.snel.com/support/how-to-set-up-lacp-bonding-on-ubuntu-18-04-with-netplan/
