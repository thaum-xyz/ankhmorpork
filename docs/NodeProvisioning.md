# Node Provisioning

## Raspberry Pi

1. Flash ubuntu-20.04-preinstalled-server-arm64+raspi.img image onto SD card
2. Boot node and go to unifi management site to discover IP. Node should be named "ubuntu".
3. Login via SSH with `ubuntu` user - `ssh ubuntu@<node_ip>`. Initial password is `ubuntu`.
4. Change password to random string. Write password down as it is necessary for next step. Later password will be disabled.
5. Add id_rsa.pub and ankhmorpork.pub to new node. Use `sshcopyid ubuntu@<node_ip>` function.

## Odroid C2

1. Flash Armbian_20.05.4_Odroidc2_focal_current_5.6.18.img image to onto SD card
2. Boot node and go to unifi management site to discover IP. Node should be named "odroidc2".
3. Login via SSH with `root` user - `ssh root@<node_ip>`. Initial password is `1234`.
4. Create user `ubuntu`. Create any password as it is necessary for node provisioning, later password will be disabled.
5. Add id_rsa.pub and ankhmorpork.pub to new node. Use `sshcopyid ubuntu@<node_ip>` function.

## AMD64

1. Boot ubuntu 20.04 server edition and follow steps on screen
