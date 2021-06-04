SHELL=/bin/bash -o pipefail

.PHONY: update
update: version-update

.PHONY: version-update
version-update:
	wget https://github.com/fluxcd/flux2/blob/main/manifests/monitoring/monitoring-config/podmonitor.yaml -O podmonitor.yaml
	wget https://github.com/fluxcd/flux2/releases/latest/download/install.yaml -O install.yaml 
