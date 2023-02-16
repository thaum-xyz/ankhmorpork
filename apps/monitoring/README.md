# What is this?

Customized kube-prometheus stack for [@paulfantom](https://github.com/paulfantom) personal homelab. This is also one of few public usages of kube-prometheus.

## How this works?

### Short version

1. `make`
2. Commit and push
3. Profit

### Long version

`kube-prometheus` is used as a library and installed with `jb`. Next customization stored in `jsonnet/main.jsonnet` is
applied. Configuration for alertmanager is stored in `raw/` directory and is picked up by jsonnet.

## Dependencies

- `jsonnet >= 0.17`
- `jsonnetfmt > 0.17`
- `jsonnet-bundler >= 0.4`
- `yamlfmt`
