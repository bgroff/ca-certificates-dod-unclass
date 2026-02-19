.PHONY: build test clean keys

build: keys
	./scripts/build.sh

test:
	./scripts/test.sh

keys:
	@if [ ! -f melange.rsa ]; then \
		echo "Generating melange signing keys..."; \
		melange keygen; \
	fi

clean:
	rm -f wolfi-base.tar wolfi-ca-certificates-dod-unclass.tar
	rm -f melange.rsa melange.rsa.pub
	rm -f sbom-*.spdx.json
	rm -rf packages/
