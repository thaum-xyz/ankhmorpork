SHELL:=/bin/bash

DIRS=\
	apps/auth \
	apps/cookbook \
	apps/homer \
	apps/monitoring

MAKEFILES=$(shell find . -name "Makefile" -not -path "*/vendor/*" -not -path "./Makefile")

.PHONY: generate
generate:
	for d in $(DIRS); do $(MAKE) -C $$d generate; done

.PHONY: upgrade
upgrade:
	for d in $(DIRS); do $(MAKE) -C $$d version-update; done

