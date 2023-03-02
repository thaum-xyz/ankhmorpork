include ../../Makefile.common

MANIFESTS_DIR=manifests/configs

version-update:
	wget -O manifests/deploy.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
	@echo "nginx-proxy potentially upgraded" >> "$(shell git rev-parse --show-toplevel)/.version-changelog"
