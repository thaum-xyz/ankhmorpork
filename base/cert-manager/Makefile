.PHONY: generate
generate: cert-manager.yaml

VERSION=$(shell cat settings.yaml | cut -d' ' -f 2 | tail -n1)
cert-manager.yaml:
	wget -O cert-manager.yaml https://github.com/jetstack/cert-manager/releases/download/v$(VERSION)/cert-manager.yaml

.PHONY: version-update
version-update:  ## Upgrade component version and image
	$(TLD)/hack/version-update.sh .
	if ! git diff-index --quiet HEAD .; then $(MAKE) generate; fi

