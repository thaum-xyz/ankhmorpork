SHELL:=/bin/bash

DIRS=\
	base/cert-manager \
	base/ingress-nginx \
	base/flux-system \
	apps/auth \
	apps/dns \
	apps/homeassistant \
	apps/homer \
	apps/monitoring \
	apps/multimedia \
	apps/parca \
	apps/portal \
	apps/recipe \
	apps/snmp \
	apps/system-update \
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

.PHONY: check
check: secrets

.PHONY: secrets
secrets:  ## Check if secrets are not leaked
	./hack/checksecrets.sh

.PHONY: validate
validate:  ## Validate kubernetes manifests
	for d in $(DIRS); do $(MAKE) -C $$d validate || exit 1; done

.PHONY: bootstrap
bootstrap:  ## Bootstrap development environment
	ggshield install -m local
