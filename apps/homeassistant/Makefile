include ../../Makefile.common

.PHONY: generate
generate: $(MANIFESTS_DIR) $(JSONNET_VENDOR)  ## Generate yaml code from jsonnet
	jsonnet -J jsonnet/vendor -c -m $(MANIFESTS_DIR) -S jsonnet/main.jsonnet
	$(MAKE) beautify
	$(MAKE) prepull

.PHONY: prepull
prepull:  ## Move jobPull.yaml to prepull directory
	mkdir -p $(MANIFESTS_DIR)/../prepull
	mv $(MANIFESTS_DIR)/homeassistant/jobPull.yaml $(MANIFESTS_DIR)/../prepull/jobPull.yaml
