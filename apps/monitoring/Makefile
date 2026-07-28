SHELL=/bin/bash -o pipefail

# This is the last component still generated from jsonnet, and it is excluded
# from the repository CI checks (see hack/validate-manifests.sh) because it
# needs a wider refactor first: the committed manifests have diverged from the
# jsonnet, so `make generate` currently reverts image bumps and drops the
# grafana_dashboard/grafana_folder provisioning labels.

MANIFESTS_DIR=manifests
JSONNET_VENDOR=jsonnet/vendor
JSONNETFMT_ARGS=-n 2 --max-blank-lines 2 --string-style s --comment-style s
KUBESCAPE_THRESHOLD=10

.PHONY: all
all: fmt generate

.PHONY: fmt
fmt:  ## Format jsonnet code
	find . -name 'vendor' -prune -o -name '*.libsonnet' -print -o -name '*.jsonnet' -print | \
		xargs -n 1 -- jsonnetfmt $(JSONNETFMT_ARGS) -i

.PHONY: generate
generate: $(MANIFESTS_DIR) $(JSONNET_VENDOR)  ## Generate yaml from jsonnet
	jsonnet -J jsonnet/vendor -c -m $(MANIFESTS_DIR) -S jsonnet/main.jsonnet
	$(MAKE) beautify

$(MANIFESTS_DIR):
	rm -rf $(MANIFESTS_DIR)
	mkdir -p $(MANIFESTS_DIR)

$(JSONNET_VENDOR):
	-cd jsonnet && jb install

.PHONY: beautify
beautify:  ## Make generated yaml readable
	for i in $(shell find $(MANIFESTS_DIR)/ -name '*.yaml'); do yq --prettyPrint --no-colors --inplace "$$i"; done

.PHONY: clean
clean:  ## Clean vendored jsonnet
	rm -rf $(JSONNET_VENDOR)

.PHONY: update
update:  ## Update jsonnet dependencies
	cd jsonnet && jb update
	rm -rf $(JSONNET_VENDOR)
	$(MAKE) generate

.PHONY: sec-scan
sec-scan:  ## Security scanning of manifests
	kubescape scan -s framework -t $(KUBESCAPE_THRESHOLD) nsa $(shell find $(MANIFESTS_DIR)/ -name '*.yaml') --exceptions 'kubescape-exceptions.json'

.PHONY: help
help:  ## Displays help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-z0-9A-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
