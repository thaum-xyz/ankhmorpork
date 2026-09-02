SHELL:=/bin/bash

.PHONY: help
help: ## Display help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: validate
validate:  ## Render every kustomization and validate it against schemas
	./hack/validate-manifests.sh

.PHONY: validate-flux
validate-flux:  ## Check that Flux Kustomization paths exist
	./hack/validate-flux-paths.sh

.PHONY: validate-configmaps
validate-configmaps:  ## Check no two Kustomizations render the same ConfigMap
	./hack/validate-configmap-ownership.sh

.PHONY: prometheusrules
prometheusrules:  ## Validate prometheus rules
	./hack/unpack-prometheus-rules.sh
	pint lint tmp/rules

.PHONY: bootstrap
bootstrap:  ## Bootstrap development environment
	ggshield install -m local
