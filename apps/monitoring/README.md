# What is this?

Customized kube-prometheus stack for @paulfantom personal homelab. This is also one of few public usages of kube-prometheus.

## How this works?

### Short version

1. `./generate.sh`
2. Commit and push
3. Profit

### Long version

`kube-prometheus` is used as a library and installed with `jb`. Next customization stored in `jsonnet/main.jsonnet` is
applied. After this `jsonnet` is used to generate `manifests/` directory and ConfigMapSecrets are copied into `manifests/`
from `configmapsecrets/` directory.
