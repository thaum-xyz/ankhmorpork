# Reboot Required

## Meaning

Node is expressing a need to be rebooted. Usually this is shown because of an unattended upgrade which included a new kernel version.

## Impact

Running with older kernel.

## Diagnosis

Log into a machine and check if latest kernel is used.

## Mitigation

Reboot the machine by following those steps:

1. Drain node with `kubectl drain node NODE_NAME`
2. Ensure all pods are moved with `kubectl describe node NODE_NAME`
3. Add silence to alertmanager silencing every alert with `node=NODE_NAME` for 1h.
4. ssh into node and run `reboot`
5. wait for node to come up
6. Make node schedulable `kubectl uncordon NODE_NAME`
7. (optional) remove silence from alertmanager.

