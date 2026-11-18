PARITY_SKILL_DIR ?= $(HOME)/.agents/skills/crystal_forge/skills/cross-language-crystal-parity
PARITY_SOURCE_DIR ?= vendor/rodney
PARITY_LANGUAGE ?= go
# Discovery runs through the verified chiasmus tree-sitter toolchain.
# The source manifest and curated ledger declare their kind scope via `kinds=`.
# See AGENTS.md.
PARITY_PARSER ?= tree-sitter

.PHONY: install update sidecars format lint test build inventory parity-verify clean

install:
	shards install

update:
	shards update

# exFAT/network volumes grow AppleDouble `._*` sidecars; a `._foo_spec.cr`
# sidecar breaks Crystal test discovery, so strip them before local gates.
sidecars:
	@find . -maxdepth 1 -name '._*' -type f -delete
	@find src spec plans scripts docs -name '._*' -type f -delete 2>/dev/null || true

format: sidecars
	crystal tool format --check

lint: sidecars
	ameba --fix
	ameba

test: sidecars
	crystal spec

build:
	crystal build src/webb.cr -o bin/webb

inventory: sidecars
	PORT_PARSER=$(PARITY_PARSER) ./scripts/check_go_port_inventory.sh "$(CURDIR)" "" "$(PARITY_SOURCE_DIR)"
	PORT_PARSER=$(PARITY_PARSER) ./scripts/check_go_source_parity.sh "$(CURDIR)" "" "$(PARITY_SOURCE_DIR)"
	PORT_PARSER=$(PARITY_PARSER) ./scripts/check_go_test_parity.sh "$(CURDIR)" "" "$(PARITY_SOURCE_DIR)"

parity-verify:
	"$(PARITY_SKILL_DIR)/scripts/verify_skill_install.sh" . $(PARITY_LANGUAGE) $(PARITY_PARSER)

clean: sidecars
	rm -rf ./temp/*
