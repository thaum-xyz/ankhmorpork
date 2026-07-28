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

.PHONY: kubescape
kubescape:  ## Security scanning of manifests
	kubescape scan --compliance-threshold 70 --exceptions './kubescape-exceptions.json' $$(find apps base core -name "*.yaml")

.PHONY: prometheusrules
prometheusrules:  ## Validate prometheus rules
	./hack/unpack-prometheus-rules.sh
	pint lint tmp/rules

.PHONY: bootstrap
bootstrap:  ## Bootstrap development environment
	ggshield install -m local
