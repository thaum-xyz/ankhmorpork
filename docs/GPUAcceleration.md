# How-to guide to enable GPU access in kubernetes

## Intel

1. Install Intel Drivers

```
sudo apt install ubuntu-restricted-addons
```

2. Add intel driver plugin DaemonSet

More info at https://github.com/intel/intel-device-plugins-for-kubernetes/tree/master/cmd/gpu_plugin

```
kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin?ref=v0.18.0
# Adapted and up-to-date version of above is in base/kube-system/device-plugins/intel-gpu-plugin.yaml
kubectl get nodes -o=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{' i915: '}{.status.allocatable.gpu\.intel\.com/i915}{'\n'}"
```

3. Add resource request to a container.

Note: without this step GPU won't get assigned

```
        resources:
          limits:
            gpu.intel.com/i915: 1
```

## Nvidia

1. Execute `ansible/20_nvidia.yml` playbook to install drivers and configure containerd
2. Restart k3s node daemon with `systemctl restart k3s-node`
3. Add nvidia driver plugin DaemonSet from `base/kube-system/device-plugins/nvidia-gpu-plugin.yaml`
4. Add resource request to a container.

Note: without this step GPU won't get assigned

```
        resources:
          limits:
            nvidia.com/gpu: 1
```

Ansible playbook is based on https://github.com/NVIDIA/k8s-device-plugin and https://dev.to/mweibel/add-nvidia-gpu-support-to-k3s-with-containerd-4j17
