.PHONY: all
all: build

.PHONY: build
build:
	docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/src -w /src node:16.19.1 bash -c \
	    'export NPM_CONFIG_PREFIX=~; npm install --no-save; npm install --no-save truffle@5.2.4; npm run build'

.PHONY: checksum
checksum:
	for f in ./build/contracts/*.json; do echo -n "$$f "; jq -j .deployedBytecode $$f | shasum; done

.PHONY: test
test:
	docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/src -w /src node:16.19.1 bash -c \
	    'export NPM_CONFIG_PREFIX=~; npm install --no-save; npm install --no-save truffle@5.2.4; npm run test'

