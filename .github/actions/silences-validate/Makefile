# Check https://github.com/fluxcd/flux2/blob/main/.github/runners/prereq.sh if
# you're updating kustomize versions.
KUSTOMIZE := ./bin/kustomize
KUSTOMIZE_VERSION ?= v4.5.7
YQ := ./bin/yq
YQ_VERSION := 4.31.2

OS ?= $(shell go env GOOS 2>/dev/null || echo linux)
ARCH ?= $(shell go env GOARCH 2>/dev/null || echo amd64)

$(KUSTOMIZE): ## Download kustomize locally if necessary.
	@echo "====> $@"
	mkdir -p $(dir $@)
	curl -sfL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F$(KUSTOMIZE_VERSION)/kustomize_$(KUSTOMIZE_VERSION)_$(OS)_$(ARCH).tar.gz" | tar zxv -C $(dir $@)
	chmod +x $@

$(YQ): ## Download yq locally if necessary.
	@echo "====> $@"
	mkdir -p $(dir $@)
	curl -sfL https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_$(OS)_$(ARCH) > $@
	chmod +x $@
