.PHONY: generate
generate: manifests/cert-manager.yaml

VERSION=$(shell cat VERSION | cut -d' ' -f1 | tail -n1)
manifests/cert-manager.yaml:
	wget -O manifests/cert-manager.yaml https://github.com/cert-manager/cert-manager/releases/download/v$(VERSION)/cert-manager.yaml

.PHONY: version-update
version-update:  ## Upgrade component version and image
	curl --retry 5 --silent --fail -H "Authorization: token $$GITHUB_TOKEN" "https://api.github.com/repos/cert-manager/cert-manager/releases/latest" 2>/dev/null | jq '.tag_name' | tr -d '"v' | tee > VERSION
	if ! git diff-index --quiet HEAD .; then $(MAKE) --always-make generate; fi

