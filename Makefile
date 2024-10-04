.PHONY: all
all: build

.PHONY: build
build:
	docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/src -w /src node:20.17.0 bash -c \
	    'export NPM_CONFIG_PREFIX=~; npm install --no-save; npx hardhat compile'

.PHONY: checksum
checksum:
	for f in ./build/contracts/*.json; do echo -n "$$f "; jq -j .deployedBytecode $$f | shasum; done

.PHONY: test
test:
	docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/src -w /src node:20.17.0 bash -c \
	    'export NPM_CONFIG_PREFIX=~; npm install --no-save; npx hardhat test'

.PHONY: workspace
workspace:
	docker run -t -i --rm --user $$(id -u):$$(id -g) -v $(PWD):/src -w /src node:20.17.0 bash -c \
	    'export NPM_CONFIG_PREFIX=~; npm install --no-save; bash'