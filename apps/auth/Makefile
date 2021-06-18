include ../Makefile.common

.PHONY: version-update
LATEST=$(shell curl https://raw.githubusercontent.com/paulfantom/dockerfiles/master/oauth2-proxy/VERSION 2>/dev/null)
CURRENT=$(shell grep version settings.yaml | cut -d':' -f2 | xargs)
version-update:
	sed -i "s/$(CURRENT)/$(LATEST)/g" settings.yaml
	if ! git diff-index --quiet HEAD .; then $(MAKE) generate; fi
