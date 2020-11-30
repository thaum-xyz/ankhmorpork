# Automatic Upgrade Plans

## System upgrade

#### What it does?

1. Cordons node
2. Drains node ignoring DaemonSets
3. Upgrades system to latest available version using `apt`.
4. Performs node reboot if necessary
5. Uncordons node (check it)

#### How to enable?

Apply label `plan.upgrade.cattle.io/system=enabled` to a node.

#### How to disable?

Either change label `plan.upgrade.cattle.io/system=enabled` to `plan.upgrade.cattle.io/system=disabled` or remove it

## K3S upgrade

#### What it does?

1. Cordons node
2. Drains node ignoring DaemonSets (only for worker nodes)
3. Downloads k3s image with new binary
4. Does binary location detection and in-place swap of it
5. Sends SIGTERM to currently running k3s process (note: restart is handled by systemd)
6. Uncordons node

#### How to enable?

Apply label `plan.upgrade.cattle.io/k3s=enabled` to a node.

#### How to disable?

Either change label `plan.upgrade.cattle.io/k3s=enabled` to `plan.upgrade.cattle.io/k3s=disabled` or remove it.
