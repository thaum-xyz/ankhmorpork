SHELL:=/bin/bash

DIRS=\
	apps/auth \
	apps/cookbook \
	apps/homer

MAKEFILES=$(shell find . -name "Makefile" -not -path "*/vendor/*" -not -path "./Makefile")

.PHONY: generate
generate:
	for d in $(DIRS); do $(MAKE) -C $$d generate; done

.PHONY: upgrade
upgrade:
	for d in $(DIRS); do ./hack/version-update.sh $$d; done
	if ! git diff-index --quiet HEAD apps base; then $(MAKE) generate; fi

