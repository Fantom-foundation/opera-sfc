.PHONY: all
all: build

.PHONY: build
build:
	docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/src -w /src node:10.5.0 bash -c \
	    'export NPM_CONFIG_PREFIX=~; npm install --no-save; npm install --no-save truffle@5.1.4; npm run build'

.PHONY: test
test:
	docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/src -w /src node:10.5.0 bash -c \
	    'export NPM_CONFIG_PREFIX=~; npm install --no-save; npm install --no-save truffle@5.1.4; npm run test'

