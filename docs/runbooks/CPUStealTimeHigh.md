# CPUStealTimeHigh

## Meaning

This alert is notifying about high CPU Steal Time when it gets over a set threshold. It is a cause based, warning type
of alert. More on the topic in https://scoutapm.com/blog/understanding-cpu-steal-time-when-should-you-be-worried

## Impact

Virtual Machines running on a hypervisor with high steal time can start running slower than expected and in extreme
cases they can slow down to a halt.

## Diagnosis

Correlate cpu usage on VMs with steal time on hypervisor.

## Mitigation

Reboot a VM with a high CPU usage or move it to a different hypervisor. Alternatively reshuffle CPU load on an offending
VM.

