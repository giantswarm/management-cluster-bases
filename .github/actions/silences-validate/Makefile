YQ := ./bin/yq
YQ_VERSION := 4.31.2

OS ?= $(shell go env GOOS 2>/dev/null || echo linux)
ARCH ?= $(shell go env GOARCH 2>/dev/null || echo amd64)

$(YQ): ## Download yq locally if necessary.
	@echo "====> $@"
	mkdir -p $(dir $@)
	curl -sfL https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_$(OS)_$(ARCH) > $@
	chmod +x $@

.PHONY: silences-validate
silences-validate: $(YQ) ## Validate silences
	@echo "====> $@ in $(directory)"

	./tools/silences-validate.sh $(directory)
