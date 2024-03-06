# Check https://github.com/fluxcd/flux2/blob/main/.github/runners/prereq.sh if
# you're updating kustomize versions.
KUSTOMIZE := ./bin/kustomize
KUSTOMIZE_VERSION ?= v5.0.3

HELM := ./bin/helm

YQ := ./bin/yq
YQ_VERSION := 4.31.2

GNU_SED := $(shell sed --version 1>/dev/null 2>&1; echo $$?)
OS ?= $(shell go env GOOS 2>/dev/null || echo linux)
ARCH ?= $(shell go env GOARCH 2>/dev/null || echo amd64)

BUILD_CATALOG_TARGETS := $(addsuffix -catalogs, $(addprefix build-,$(notdir $(wildcard management-clusters/*))))
BUILD_MC_TARGETS := $(addprefix build-,$(notdir $(wildcard management-clusters/*)))

BUILD_CRD_TARGETS := build-common-crds build-common-flux-v2-crds build-flux-app-crds build-flux-app-v2-crds build-giantswarm-crds

BUILD_FLUX_APP_TARGETS := build-flux-app-customer build-flux-app-giantswarm

BASE_REPOSITORY := giantswarm/management-cluster-bases
MCB_BRANCH ?= bootstrap-1.25

.PHONY: build-flux-app-vaultless-helper
ifeq ($(VAULTLESS),1)
build-flux-app-vaultless-helper: $(YQ)
ifndef TMP_BASE
	$(error $$TMP_BASE env var is not defined, this is a bug and has to be fixed in the Makefile.custom.mk)
endif
	$(YQ) e -i '.patchesStrategicMerge += ["https://raw.githubusercontent.com/${BASE_REPOSITORY}/${MCB_BRANCH}/extras/vaultless/patch-delete-vault-cronjob.yaml"]' $(TMP_BASE)/kustomization.yaml
	$(YQ) e -i '.patchesStrategicMerge += ["https://raw.githubusercontent.com/${BASE_REPOSITORY}/${MCB_BRANCH}/extras/vaultless/patch-kustomize-controller.yaml"]' $(TMP_BASE)/kustomization.yaml
else
build-flux-app-vaultless-helper:
	@# noop
endif

# TODO Change https://github.com/giantswarm/apptestctl/blame/90942be9c1c2fd58f765bc191d8ef5889717eb4b/hack/sync-crds.sh to use these instead (ATS will need make too tho)
.PHONY: build-catalogs-with-defaults
build-catalogs-with-defaults: $(KUSTOMIZE) ## Build Giant Swarm catalogs with default configuration
	@echo "====> $@"
	mkdir -p output
	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone https://github.com/${BASE_REPOSITORY}//bases/catalogs?ref=${MCB_BRANCH} -o output/catalogs-with-defaults.yaml

.PHONY: $(BUILD_CATALOG_TARGETS)
$(BUILD_CATALOG_TARGETS): $(KUSTOMIZE) ## Build Giant Swarm catalogs for management clusters
	@echo "====> $@"
	mkdir -p output
	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone management-clusters/$(subst build-,,$(subst -catalogs,,$@))/catalogs -o output/$(subst build-,,$(subst -catalogs,,$@))-catalogs.yaml

.PHONY: $(BUILD_CRD_TARGETS)
build-common-crds:  ## Builds https://github.com/giantswarm/management-cluster-bases//bases/crds/common
build-common-flux-v2-crds:  ## Builds https://github.com/giantswarm/management-cluster-bases//bases/crds/common-flux-v2
build-flux-app-crds:  ## Builds https://github.com/giantswarm/management-cluster-bases//bases/crds/flux-app
build-flux-app-v2-crds:  ## Builds https://github.com/giantswarm/management-cluster-bases//bases/crds/flux-app-v2
build-giantswarm-crds:  ## Builds https://github.com/giantswarm/management-cluster-bases//bases/crds/giantswarm
$(BUILD_CRD_TARGETS): $(KUSTOMIZE) ## Build CRDs
	@echo "====> $@"

	rm -rf /tmp/mcb.${MCB_BRANCH}
	git clone -b $(MCB_BRANCH) https://github.com/${BASE_REPOSITORY} /tmp/mcb.${MCB_BRANCH}

	mkdir -p output

	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone /tmp/mcb.${MCB_BRANCH}/bases/crds/$(subst build-,,$(subst -crds,,$@)) -o output/$(subst build-,,$(subst -crds,,$@))-crds.yaml

.PHONY: $(BUILD_FLUX_APP_TARGETS)
build-flux-app-customer: ## Can take FLUX_MAJOR_VERSION=1|2|... DISABLE_KYVERNO=1 DISABLE_VPA=1 and FORCE_CRDS=1.
build-flux-app-giantswarm: ## Can take FLUX_MAJOR_VERSION=1|2|... DISABLE_VPA=1.
$(BUILD_FLUX_APP_TARGETS): SUFFIX = $(lastword $(subst -, ,$@))
$(BUILD_FLUX_APP_TARGETS): TMP_BASE = bases/flux-app-tmp-$(SUFFIX)
$(BUILD_FLUX_APP_TARGETS): $(KUSTOMIZE) $(HELM) $(YQ)
	@echo "====> $@"

	rm -rf /tmp/mcb.${MCB_BRANCH}
	git clone -b $(MCB_BRANCH) https://github.com/${BASE_REPOSITORY} /tmp/mcb.${MCB_BRANCH}

	mkdir -p output

	rm -rf $(TMP_BASE)

ifeq ($(FLUX_MAJOR_VERSION),1)
	cp -a /tmp/mcb.${MCB_BRANCH}/bases/flux-app/${SUFFIX} $(TMP_BASE)
else
	cp -a /tmp/mcb.${MCB_BRANCH}/bases/flux-app-v${FLUX_MAJOR_VERSION}/${SUFFIX} $(TMP_BASE)
endif

	@# This will run extra yq calls if VAULTLESS=1
	@$(MAKE) VAULTLESS=$(SUFFIX:giantswarm=1) TMP_BASE=$(TMP_BASE) build-flux-app-vaultless-helper
ifeq ($(DISABLE_KYVERNO),1)
	@# This makes sense only for build-flux-app-cluster, but makes no harm to other targets
	$(YQ) e -i '.resources -= ["resource-kyverno-policies.yaml"]' $(TMP_BASE)/kustomization.yaml
endif
ifeq ($(DISABLE_VPA),1)
	$(YQ) e -i '(.helmCharts[] | select(.name == "flux-app") | .valuesInline.verticalPodAutoscaler.enabled) = false' $(TMP_BASE)/kustomization.yaml
endif
ifeq ($(FORCE_CRDS),1)
	@# This makes sense only for build-flux-app-cluster, but makes no charm to other targets
	$(YQ) e -i '(.helmCharts[] | select(.name == "flux-app") | .valuesInline.crds.install) = true' $(TMP_BASE)/kustomization.yaml
endif

ifdef BOOTSTRAP_CLUSTER
ifneq ($(filter build-flux-app-customer,$(MAKECMDGOALS)),)
	$(YQ) e -i '(.helmCharts[] | select(.name == "flux-app") | .valuesInline.cilium.enforce) = false' $(TMP_BASE)/kustomization.yaml
	$(YQ) e -i '(.helmCharts[] | select(.name == "flux-app") | .valuesInline.podMonitors.enabled) = false' $(TMP_BASE)/kustomization.yaml
	$(YQ) e -i '(.helmCharts[] | select(.name == "flux-app") | .valuesInline.policyException.enforce) = false' $(TMP_BASE)/kustomization.yaml
endif
endif
	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone --enable-helm --helm-command="$(HELM)" $(TMP_BASE) -o output/flux-app-v${FLUX_MAJOR_VERSION}-$(SUFFIX).yaml
	rm -rf $(TMP_BASE)

.PHONY: $(BUILD_MC_TARGETS)
$(BUILD_MC_TARGETS): $(KUSTOMIZE) $(HELM) $(YQ)
	@echo "====> $@"
	mkdir -p output
	$(KUSTOMIZE) build --enable-alpha-plugins --load-restrictor LoadRestrictionsNone --enable-helm --helm-command="$(HELM)" management-clusters/$(subst build-,,$@) > output/$(subst build-,,$@).prep.yaml
	echo '---' >> output/$(subst build-,,$@).prep.yaml
	$(KUSTOMIZE) build --enable-alpha-plugins --load-restrictor LoadRestrictionsNone --enable-helm --helm-command="$(HELM)" management-clusters/$(subst build-,,$@)/extras >> output/$(subst build-,,$@).prep.yaml
	# extract variables from the `flux` Kustomization CR
	$(YQ) e 'select(.kind == "Kustomization") | select(.metadata.name == "flux") | .spec.postBuild.substitute.[] | "export " + key + "=" + @sh' output/$(subst build-,,$@).prep.yaml > output/$(subst build-,,$@).env
	# extract variables as scope for `envsubst` to not risk replacing too much
	$(YQ) e 'select(.kind == "Kustomization") | select(.metadata.name == "flux") | .spec.postBuild.substitute.[] | "$$$$" + key' output/$(subst build-,,$@).prep.yaml | xargs | tr ' ' ':' > output/$(subst build-,,$@).envsubst
	# add the extracted scope to `.env` file
	echo "export envsubst_scope=\$$(cat output/$(subst build-,,$@).envsubst)" >> output/$(subst build-,,$@).env
	# run the substitution
	. output/$(subst build-,,$@).env && cat output/$(subst build-,,$@).prep.yaml | envsubst "$$envsubst_scope" > output/$(subst build-,,$@).yaml
	[ $(GNU_SED) -eq 0 ] && sed -i 's/$$$${/$${/g' output/$(subst build-,,$@).yaml || sed -i "" 's/$$$${/$${/g' output/$(subst build-,,$@).yaml
	rm output/$(subst build-,,$@).prep.yaml

$(KUSTOMIZE): ## Download kustomize locally if necessary.
	@echo "====> $@"
	mkdir -p $(dir $@)
	curl -sfL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F$(KUSTOMIZE_VERSION)/kustomize_$(KUSTOMIZE_VERSION)_$(OS)_$(ARCH).tar.gz" | tar zxv -C $(dir $@)
	chmod +x $@

$(HELM): ## Download helm locally if necessary.
	@echo "====> $@"
	curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR=$(dir $@) USE_SUDO=false bash

$(YQ): ## Download yq locally if necessary.
	@echo "====> $@"
	mkdir -p $(dir $@)
	curl -sfL https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_$(OS)_$(ARCH) > $@
	chmod +x $@
