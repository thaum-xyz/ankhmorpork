SHELL:=/bin/bash

# Kept in sync with .github/workflows/docs.yml by the zensical customManager
# in .github/renovate.json, which matches both spellings.
ZENSICAL_VERSION:=0.0.59

# Homebrew's python3 has no pyyaml on the workstations this runs on; the system
# one does. CI passes PYTHON=python3 so setup-python's interpreter is used.
PYTHON?=/usr/bin/python3

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
	$(PYTHON) hack/validate-configmap-ownership.py

.PHONY: lint-shell
lint-shell:  ## Run shellcheck over every tracked shell script
	git ls-files '*.sh' | xargs shellcheck

.PHONY: validate-alertmanager
validate-alertmanager:  ## Check the rendered Alertmanager config with amtool
	./hack/validate-alertmanager-config.sh

.PHONY: prometheusrules
prometheusrules:  ## Validate prometheus rules
	./hack/unpack-prometheus-rules.sh
	pint lint tmp/rules

.PHONY: bootstrap
bootstrap:  ## Bootstrap development environment
	ggshield install -m local

.PHONY: docs
docs:  ## Serve the documentation site locally with live reload
	uvx zensical==$(ZENSICAL_VERSION) serve

.PHONY: docs-build
docs-build:  ## Build the documentation site into ./site
	uvx zensical==$(ZENSICAL_VERSION) build --clean

.PHONY: docs-reference
docs-reference:  ## Regenerate the derivable reference pages under docs/reference
	$(PYTHON) hack/generate-docs-reference.py

.PHONY: docs-reference-check
docs-reference-check: docs-reference  ## Fail if the generated reference pages are stale
	@# git-status, not git-diff: diff ignores untracked files, so a page that was
	@# never generated would pass silently.
	@out="$$(git status --porcelain -- docs/reference/apps.md docs/reference/admission-policies.md docs/reference/flux-kustomizations.md docs/reference/helm-releases.md docs/reference/ingress.md)"; \
	if [ -n "$$out" ]; then \
		echo "$$out"; \
		echo; \
		echo "Generated reference pages are out of date. Run 'make docs-reference' and commit."; \
		exit 1; \
	fi

.PHONY: docs-lint
docs-lint:  ## Check docs for broken links, missing paths, unknown names and stale-prone prose
	$(PYTHON) hack/lint-docs.py
