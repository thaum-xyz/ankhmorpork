# LACP

## Netplan

After ubuntu installation LACP on bond interface may not be enabled causing networking issues.

Following configuration enables LACP in netplan:
```
network:
  bonds:
    bond0:
      addresses:
      - 192.168.2.3/24
      gateway4: 192.168.2.1
      interfaces:
      - enp16s0f0
      - enp16s0f1
      - enp16s0f2
      - enp16s0f3
      nameservers:
        addresses:
        - 192.168.2.1
        - 1.1.1.1
        search:
        - ankhmorpork.thaum.xyz
      parameters:
        mode: 802.3ad
        lacp-rate: fast
        mii-monitor-interval: 100
  ethernets:
    enp16s0f0: {}
    enp16s0f1: {}
    enp16s0f2: {}
    enp16s0f3: {}
  version: 2
```

Information taken from https://www.snel.com/support/how-to-set-up-lacp-bonding-on-ubuntu-18-04-with-netplan/
