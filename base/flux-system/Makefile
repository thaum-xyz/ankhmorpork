include ../../Makefile.common

MANIFESTS_DIR=manifests/configs

.PHONY: version-update
version-update:
	# wget -O manifests/podmonitor.yaml https://raw.githubusercontent.com/fluxcd/flux2/main/manifests/monitoring/monitoring-config/podmonitor.yaml
	wget -O manifests/install.yaml https://github.com/fluxcd/flux2/releases/latest/download/install.yaml
