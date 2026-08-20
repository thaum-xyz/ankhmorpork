# What is this?

Customized kube-prometheus stack for [@paulfantom](https://github.com/paulfantom) personal homelab.

## How this works?

`manifests/` holds plain Kubernetes YAML and is the source of truth. Flux
applies the directory directly (see `base/flux-apps/monitoring.yaml`), so
editing a manifest and pushing is all that is needed.

This used to be generated from jsonnet, with `kube-prometheus` vendored as a
library. That layer was removed: the committed manifests had drifted from the
jsonnet, so regenerating reverted image bumps and dropped hand-applied changes.
Renovate now bumps the images in `manifests/` directly.

Two consequences worth knowing:

- upstream `kube-prometheus` and mixin changes no longer arrive automatically;
  picking one up means porting the relevant manifest by hand.
- the alertmanager config template lives in
  `manifests/alertmanager/configTemplate.yaml`. It used to be assembled from
  `raw/alertmanager-config.yaml.gtpl`, which held an identical copy.

`download-dashboard-from-cluster.sh` dumps the Grafana dashboard ConfigMaps out
of the running cluster into `dashboards/`, which is handy when a dashboard was
edited in the UI and needs to be written back here.
