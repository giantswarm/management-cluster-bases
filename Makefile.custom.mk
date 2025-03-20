# Check https://github.com/fluxcd/flux2/blob/main/.github/runners/prereq.sh if
# you're updating kustomize versions.
KUSTOMIZE := ./bin/kustomize
KUSTOMIZE_VERSION ?= v4.5.7

YQ := ./bin/yq
YQ_VERSION := 4.31.2

GNU_SED := $(shell sed --version 1>/dev/null 2>&1; echo $$?)
OS ?= $(shell go env GOOS 2>/dev/null || echo linux)
ARCH ?= $(shell go env GOARCH 2>/dev/null || echo amd64)

.PHONY: build-catalogs-with-defaults
build-catalogs-with-defaults: $(KUSTOMIZE) ## Build Giant Swarm catalogs with default configuration
	@echo "====> $@"
	mkdir -p output
	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone bases/catalogs -o output/catalogs-with-defaults.yaml


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

BUILD_CRD_TARGETS := build-common-crds build-common-flux-v2-crds build-flux-app-crds build-flux-app-v2-crds build-giantswarm-crds

.PHONY: $(BUILD_CRD_TARGETS)
build-common-flux-v2-crds:  ## Builds bases/crds/common-flux-v2
build-flux-app-v2-crds:  ## Builds bases/crds/flux-app-v2
build-giantswarm-crds:  ## Builds bases/crds/giantswarm
$(BUILD_CRD_TARGETS): $(KUSTOMIZE) ## Build CRDs
	@echo "====> $@"

	mkdir -p output

	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone bases/crds/$(subst build-,,$(subst -crds,,$@)) -o output/$(subst build-,,$(subst -crds,,$@))-crds.yaml

silences-validate: $(YQ) ## Validate silences
	@echo "====> $@"

	./.github/actions/silences-validate/silences-validate.sh $(directory)
