.PHONY: install update format lint test build

install:
	BEADS_DIR=$$(pwd)/.beads shards install

update:
	BEADS_DIR=$$(pwd)/.beads shards update

format:
	crystal tool format --check

lint:
	ameba --fix
	ameba

test:
	crystal spec

build:
	crystal build src/webb.cr -o bin/webb

clean:
	rm -rf ./temp/*