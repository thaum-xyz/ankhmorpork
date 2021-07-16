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
	for d in $(DIRS); do $(MAKE) -C $$d generate || exit 1; done

.PHONY: upgrade
upgrade:
	for d in $(DIRS); do $(MAKE) -C $$d version-update || exit 1; done

.PHONY: check
check: secrets

.PHONY: secrets
secrets:
	./hack/checksecrets.sh

.PHONY: validate
validate:
	for d in $(DIRS); do $(MAKE) -C $$d validate || exit 1; done
