SHELL:=/bin/bash

DIRS=\
	apps/homeassistant \
	apps/homer \
	apps/monitoring \
	apps/unifi \
	apps/tandoor

HELMDIRS=\
	apps/atuin \
	apps/changedetection \
	apps/datalake-logs \
	apps/datalake-metrics \
	apps/descheduler \
	apps/external-dns \
	apps/jellyfin \
	apps/minio \
	apps/opencost \
	apps/photos \
	apps/promtail \
	apps/scripts-mon \
	apps/system-kured \
	base/cert-manager \
	base/cnpg-system \
	base/external-secrets \
	base/flux-system \
	base/longhorn-system \
	base/metallb-system \
	base/node-feature-discovery \
	base/node-problem-detector \
	base/topolvm \
	base/traefik

MAKEFILES=$(shell find . -name "Makefile" -not -path "*/vendor/*" -not -path "./Makefile")

.PHONY: help
help: ## Display help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: generate
generate:  ## Generate all manifests
	for d in $(DIRS); do $(MAKE) -C $$d generate || exit 1; done

.PHONY: upgrade
upgrade:  ## Update all components and their versions
	for d in $(DIRS); do $(MAKE) -C $$d version-update || exit 1; done
	for d in $(HELMDIRS); do hack/helm-updater.sh "$$d" || exit 1; done

.PHONY: validate
validate:  ## Validate kubernetes manifests
	for d in $(DIRS); do $(MAKE) -C $$d validate || exit 1; done

.PHONY: kubescape
kubescape:  ## Validate kubernetes manifests
	kubescape scan --compliance-threshold 70 --exceptions './kubescape-exceptions.json' $$(find apps base -name "*.yaml" -not -path "*/jsonnet/*" -not -path "*/vendor/*" -not -name "settings.yaml")

.PHONY: prometheusrules
prometheusrules:  ## Validate prometheus rules
	./hack/unpack-prometheus-rules.sh
	pint lint tmp/rules

.PHONY: bootstrap
bootstrap:  ## Bootstrap development environment
	ggshield install -m local
