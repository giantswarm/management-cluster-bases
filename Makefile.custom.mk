# Check https://github.com/fluxcd/flux2/blob/main/.github/runners/prereq.sh if
# you're updating kustomize versions. Keep this matching the kustomize version
# shipped by kustomize-controller, so a local build behaves like a cluster one.
KUSTOMIZE := ./bin/kustomize
KUSTOMIZE_VERSION ?= v5.6.0

YQ := ./bin/yq
YQ_VERSION := 4.31.2

# Keep this matching the appVersion of the crossplane chart pinned in
# extras/crossplane/helmrelease-crossplane.yaml, so render behaves like the MCs.
CROSSPLANE := ./bin/crossplane
CROSSPLANE_VERSION ?= v1.15.2

GNU_SED := $(shell sed --version 1>/dev/null 2>&1; echo $$?)
OS ?= $(shell go env GOOS 2>/dev/null || echo linux)
ARCH ?= $(shell go env GOARCH 2>/dev/null || echo amd64)

.PHONY: build-catalogs-with-defaults
build-catalogs-with-defaults: $(KUSTOMIZE) ## Build Giant Swarm catalogs with default configuration
	@echo "====> $@"
	mkdir -p output
	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone bases/catalogs -o output/catalogs-with-defaults.yaml


# Deliberately no --load-restrictor: management clusters consume these
# collections as remote bases, and kustomize enforces LoadRestrictionsRootOnly
# inside the git clone it creates for them, no matter what --load-restrictor
# says. Building with the default here is what catches what kustomize-controller
# would reject.
.PHONY: build-collections
build-collections: $(KUSTOMIZE) ## Build every collection stage the way kustomize-controller would
	@echo "====> $@"
	@rc=0; \
	for dir in bases/collections/*/stages/*/; do \
		if $(KUSTOMIZE) build "$$dir" >/dev/null; then \
			echo "ok    $$dir"; \
		else \
			echo "FAIL  $$dir"; \
			rc=1; \
		fi; \
	done; \
	exit $$rc

# Needs a Docker-compatible daemon: render runs each composition function as a
# container. With podman, export DOCKER_HOST=unix://$$XDG_RUNTIME_DIR/podman/podman.sock.
.PHONY: test-compositions
test-compositions: $(CROSSPLANE) ## Render every Crossplane composition example
	@echo "====> $@"
	./tools/test-compositions.sh $(CROSSPLANE)

$(KUSTOMIZE): ## Download kustomize locally if necessary.
	@echo "====> $@"
	mkdir -p $(dir $@)
	curl -sfL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F$(KUSTOMIZE_VERSION)/kustomize_$(KUSTOMIZE_VERSION)_$(OS)_$(ARCH).tar.gz" | tar zxv -C $(dir $@)
	chmod +x $@

$(CROSSPLANE): ## Download the crossplane CLI locally if necessary.
	@echo "====> $@"
	mkdir -p $(dir $@)
	curl -sfL "https://releases.crossplane.io/stable/$(CROSSPLANE_VERSION)/bin/$(OS)_$(ARCH)/crank" > $@
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

silences-report-expired: $(YQ) ## Validate silences
	@echo "====> $@"

	./.github/actions/silences-report-expired/silences-report-expired.sh $(directory)
