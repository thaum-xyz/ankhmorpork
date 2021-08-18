SHELL=/bin/bash -o pipefail

.PHONY: update
update: version-update

.PHONY: version-update
version-update:
	# wget -O podmonitor.yaml https://raw.githubusercontent.com/fluxcd/flux2/main/manifests/monitoring/monitoring-config/podmonitor.yaml
	wget -O install.yaml https://github.com/fluxcd/flux2/releases/latest/download/install.yaml
