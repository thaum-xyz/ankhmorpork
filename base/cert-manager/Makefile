.PHONY: generate
generate: cert-manager.yaml

VERSION=$(shell cat VERSION | cut -d' ' -f1 | tail -n1)
cert-manager.yaml:
	wget -O cert-manager.yaml https://github.com/jetstack/cert-manager/releases/download/v$(VERSION)/cert-manager.yaml

.PHONY: version-update
version-update:  ## Upgrade component version and image
	curl --retry 5 --silent --fail -H "Authorization: token $$GITHUB_TOKEN" "https://api.github.com/repos/jetstack/cert-manager/releases/latest" 2>/dev/null | jq '.tag_name' | tr -d '"v' > VERSION
	if ! git diff-index --quiet HEAD .; then $(MAKE) --always-make generate; fi

