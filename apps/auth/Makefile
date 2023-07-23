include ../../Makefile.common

.PHONY: version-update
LATEST=$(shell curl https://raw.githubusercontent.com/paulfantom/dockerfiles/master/oauth2-proxy/VERSION 2>/dev/null)
CURRENT=$(shell grep version settings.yaml | cut -d':' -f2 | xargs)
version-update:
	sed -Ei.bak "s/$(CURRENT)/$(LATEST)/g" settings.yaml
	rm *.bak
	@echo "oauth2-proxy/oauth2-proxy from $(CURRENT) to $(LATEST)" >> "$(shell git rev-parse --show-toplevel)/.version-changelog"
	if ! git diff-index --quiet HEAD .; then $(MAKE) generate; fi
