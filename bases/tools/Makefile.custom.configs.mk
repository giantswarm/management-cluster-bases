SHELL = /bin/sh

SHARED_CONFIGS_BRANCH ?= main

TMPDIR := $(shell mktemp -d)

assemble-config:
	@git clone --quiet --depth 1 --branch "${SHARED_CONFIGS_BRANCH}" https://github.com/giantswarm/shared-configs $$TMPDIR
	@rm -rf ./default
	@mv $$TMPDIR/default ./
	@rm -rf ./include
	@mv $$TMPDIR/include ./
	@rm -rf $$TMPDIR

assemble-config-ssh:
	@git clone --quiet --depth 1 --branch "${SHARED_CONFIGS_BRANCH}" git@github.com:giantswarm/shared-configs.git $$TMPDIR
	@rm -rf ./default
	@mv $$TMPDIR/default ./
	@rm -rf ./include
	@mv $$TMPDIR/include ./
	@rm -rf $$TMPDIR
