.PHONY: generate
generate: metallb.yaml

VERSION=$(shell cat VERSION | cut -d' ' -f1 | tail -n1 )
metallb.yaml:
	wget -O metallb.yaml https://raw.githubusercontent.com/metallb/metallb/v$(VERSION)/manifests/metallb.yaml

.PHONY: version-update
version-update:  ## Upgrade component version and image
	curl --retry 5 --silent --fail -H "Authorization: token $$GITHUB_TOKEN" "https://api.github.com/repos/metallb/metallb/releases/latest" 2>/dev/null | jq '.tag_name' | tr -d '"v' | sed 's/metallb-chart-//' > VERSION
	@echo "metallb/metallb to $(VERSION)" >> "$(shell git rev-parse --show-toplevel)/.version-changelog"
	if ! git diff-index --quiet HEAD .; then $(MAKE) --always-make generate; fi
