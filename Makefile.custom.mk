# Check https://github.com/fluxcd/flux2/blob/main/.github/runners/prereq.sh if
# you're updating kustomize versions.
KUSTOMIZE := ./bin/kustomize
KUSTOMIZE_VERSION ?= v4.5.7

YQ := ./bin/yq
YQ_VERSION := 4.31.2

FLUX_APP_REPOSITORY := https://giantswarm.github.io/giantswarm-catalog/
FLUX_APP_VERSION := v0.23.1
FLUX_VERSION := v0.41.2

KONFIGURE_IMAGE_TAG := 0.14.4
KUSTOMIZE_CONTROLLER_IMAGE_TAG := v0.35.1

GNU_SED := $(shell sed --version 1>/dev/null 2>&1; echo $$?)
OS ?= $(shell go env GOOS 2>/dev/null || echo linux)
ARCH ?= $(shell go env GOARCH 2>/dev/null || echo amd64)

.PHONY: all
all: ensure-versions

.PHONY: ensure-versions
ensure-versions: $(YQ) download-upstream-crds
	@echo "====> $@"
	head output/flux-$(FLUX_VERSION).crds.yaml
	cp output/flux-$(FLUX_VERSION).crds.yaml bases/crds/flux-app/crds.yaml
	head bases/crds/flux-app/crds.yaml

ifeq ($(GNU_SED),0)
	sed -i "0,/version:/{s!repo: .*!repo: $(FLUX_APP_REPOSITORY)!g}" bases/flux-app/customer/kustomization.yaml
	sed -i "0,/version:/{s!repo: .*!repo: $(FLUX_APP_REPOSITORY)!g}" bases/flux-app/giantswarm/kustomization.yaml

	sed -i "0,/version:/{s/version: .*/version: $(FLUX_APP_VERSION)/g}" bases/flux-app/customer/kustomization.yaml
	sed -i "0,/version:/{s/version: .*/version: $(FLUX_APP_VERSION)/g}" bases/flux-app/giantswarm/kustomization.yaml

	sed -i "0,/image: giantswarm\/konfigure/{s/giantswarm\/konfigure:.*/giantswarm\/konfigure:$(KONFIGURE_IMAGE_TAG)/g}" bases/flux-app/giantswarm/patch-kustomize-controller.yaml
	sed -i "0,/image: giantswarm\/kustomize-controller/{s/giantswarm\/kustomize-controller:.*/giantswarm\/kustomize-controller:$(KUSTOMIZE_CONTROLLER_IMAGE_TAG)/g}" bases/flux-app/giantswarm/patch-kustomize-controller.yaml
else
	sed -i "" "1,/version:/ s/version: .*/version: $(FLUX_APP_VERSION)/g" bases/flux-app/customer/kustomization.yaml
	sed -i "" "1,/version:/ s/version: .*/version: $(FLUX_APP_VERSION)/g" bases/flux-app/giantswarm/kustomization.yaml

	sed -i "" "1,/image: giantswarm\/konfigure/ s/giantswarm\/konfigure:.*/giantswarm\/konfigure:$(KONFIGURE_IMAGE_TAG)/g" bases/flux-app/giantswarm/patch-kustomize-controller.yaml
	sed -i "" "1,/image: giantswarm\/kustomize-controller/ s/giantswarm\/kustomize-controller:.*/giantswarm\/kustomize-controller:$(KUSTOMIZE_CONTROLLER_IMAGE_TAG)/g" bases/flux-app/giantswarm/patch-kustomize-controller.yaml
endif
	git clean -fxd bases/flux-app/

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

download-upstream-install:
	@echo "====> $@"
	mkdir -p output
	curl -sfL "https://github.com/fluxcd/flux2/releases/download/$(FLUX_VERSION)/install.yaml" > output/flux-$(FLUX_VERSION).install.yaml

download-upstream-crds: download-upstream-install $(YQ)
	@echo "====> $@"
	$(YQ) eval-all 'select(.kind == "CustomResourceDefinition")' output/flux-$(FLUX_VERSION).install.yaml > output/flux-$(FLUX_VERSION).crds.yaml
