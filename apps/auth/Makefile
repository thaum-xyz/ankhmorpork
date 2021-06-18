SHELL=/bin/bash -o pipefail

MANIFESTS_DIR=manifests
JSONNET_VENDOR=jsonnet/vendor
JSONNETFMT_ARGS=-n 2 --max-blank-lines 2 --string-style s --comment-style s

.PHONY: all
all: fmt generate

.PHONY: fmt
fmt:
	find . -name 'vendor' -prune -o -name '*.libsonnet' -print -o -name '*.jsonnet' -print | \
		xargs -n 1 -- jsonnetfmt $(JSONNETFMT_ARGS) -i

.PHONY: generate
generate: $(MANIFESTS_DIR) $(JSONNET_VENDOR)
	jsonnet -J jsonnet/vendor -c -m $(MANIFESTS_DIR) -S jsonnet/main.jsonnet
	$(MAKE) beautify

$(MANIFESTS_DIR):
	rm -rf $(MANIFESTS_DIR)
	mkdir -p $(MANIFESTS_DIR)

$(JSONNET_VENDOR):
	cd jsonnet && jb install

.PHONY: beautify
beautify:
	for i in $(shell find manifests/ -name *.yaml); do mv "$$i" "$$i.bak"; yamlfmt < "$$i.bak" > "$$i"; rm "$$i.bak"; done

.PHONY: update
update:
	cd jsonnet && jb update
	rm -rf $(JSONNET_VENDOR)
	$(MAKE) generate

.PHONY: version-update
LATEST=$(shell curl https://raw.githubusercontent.com/paulfantom/dockerfiles/master/oauth2-proxy/VERSION 2>/dev/null)
CURRENT=$(shell grep version jsonnet/settings.yaml | cut -d':' -f2 | xargs)
version-update:
	sed -i "s/$(CURRENT)/$(LATEST)/g" jsonnet/settings.yaml
	if ! git diff-index --quiet HEAD .; then $(MAKE) generate; fi
