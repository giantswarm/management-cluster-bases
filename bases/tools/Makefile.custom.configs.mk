TMPDIR := $(shell mktemp -d)

assemble-config:
	@git clone --quiet https://github.com/giantswarm/shared-configs $$TMPDIR
	@mv $$TMPDIR/default ./
	@mv $$TMPDIR/include ./
	@rm -rf $$TMPDIR
