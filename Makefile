SHELL:=/bin/bash

DIRS=\
	apps/auth \
	apps/homer \
	apps/monitoring \
	apps/news \
	apps/recipe \
	apps/unifi \
	apps/system-update

MAKEFILES=$(shell find . -name "Makefile" -not -path "*/vendor/*" -not -path "./Makefile")

.PHONY: generate
generate:
	for d in $(DIRS); do $(MAKE) -C $$d generate; done

.PHONY: upgrade
upgrade:
	for d in $(DIRS); do $(MAKE) -C $$d version-update; done

.PHONY: check
check: secrets

.PHONY: secrets
secrets:
	./hack/checksecrets.sh
