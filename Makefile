SHELL:=/bin/bash

DIRS=\
	base/cert-manager \
	base/flux-system \
	apps/auth \
	apps/datalake-metrics \
	apps/dns \
	apps/homeassistant \
	apps/homer \
	apps/monitoring \
	apps/unifi

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
