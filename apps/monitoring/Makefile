include ../../Makefile.common

.PHONY: generate
generate: $(MANIFESTS_DIR) $(JSONNET_VENDOR)
	jsonnet -J jsonnet/vendor -c -m $(MANIFESTS_DIR) -S jsonnet/main.jsonnet
	$(MAKE) beautify
	$(MAKE) raw

.PHONY: raw
raw:
	./raw/populate.sh

