# Development

## Quick Reference

```bash
make install        # shards install
make update         # shards update
make format         # Check formatting (crystal tool format --check)
make lint           # Lint and auto-fix (ameba --fix, then ameba)
make test           # Run specs (crystal spec, 239 examples)
make build          # Compile the CLI to bin/webb
make inventory      # Parity ledger gates (tree-sitter backend, vendor/rodney)
make parity-verify  # Verify the installed parity skill + discovery backend
make docs-lint      # rumdl check README.md docs/ (skipped when rumdl is absent)
make clean          # Remove temp/ contents and AppleDouble sidecars
```

Every target except `install`, `update`, `build`, `parity-verify`, and `clean`
runs the `sidecars` step first, which deletes macOS AppleDouble `._*` files (see
[Environment notes](#environment-notes)).

Run the CLI straight from the build:

```bash
bin/webb start
bin/webb open https://example.com
bin/webb title
bin/webb stop
```

## Dependency: `rod` Crystal Shard

This project depends on the `rod` Crystal shard (`github: dsisnero/rod`, tracked
on `branch: main`), a port of `go-rod/rod`. The shard is declared in `shard.yml`
and installed under `lib/rod/`.

The shard source at `lib/rod/` may contain patches that fix parity issues. Any
deliberate divergence from upstream rod is documented in the shard's own
`plans/parity.md` and, when it affected this port, in `plans/history-shard.md`.
`shard_issues/` is empty: every gap found so far landed upstream in the shard
pin.

## Porting Workflow

1. **Reference the Go source**: Find the function/test in
   `vendor/rodney/main.go` or `vendor/rodney/main_test.go`
2. **Check parity inventory**: `plans/inventory/go_port_inventory.tsv` tracks
   port status for every Go construct
3. **Translate to Crystal**: Preserve behavior exactly; use Crystal idioms
   (snake_case methods, `case`/`when`, `JSON::Serializable`)
4. **Port corresponding tests**: Create Crystal specs that mirror the Go test
   logic, or characterization specs where upstream has no test — red first, then
   green
5. **Run quality gates**:
   `make format && make lint && make test && make build && make inventory`
6. **Update the ledger**: mark items as `ported` in
   `plans/inventory/go_port_inventory.tsv`, refresh `plans/parity.md`'s
   **Where we are** block, and re-run `make inventory`
7. **Update `CHANGELOG.md`** when the change is visible outside the port's own
   bookkeeping (a new command or flag, a shard pin move, a divergence change);
   per-symbol progress belongs in the plans, not the changelog

## Parity Tooling

The parity gate is not implemented in this repo. `scripts/*.sh` are thin
forwarding wrappers around the installed cross-language parity skill
(`PARITY_SKILL_DIR`, default
`~/.agents/skills/crystal_forge/skills/cross-language-crystal-parity`); update
the skill, not the wrappers, when gate behavior changes. Never copy the skill's
Ruby helpers back into `scripts/`.

The curated ledger is discovered with tree-sitter (`parser=tree-sitter` in the
manifest headers and `<manifest>.metadata.json` sidecars), matching the policy
recorded in `AGENTS.md`. `make inventory` runs all three checks (port inventory,
source parity, test parity) against `vendor/rodney`; `make parity-verify` checks
the installed skill and reports `PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter`.

```bash
PARITY_SKILL_DIR="${HOME}/.agents/skills/crystal_forge/skills/cross-language-crystal-parity"
"${PARITY_SKILL_DIR}/scripts/install_chiasmus_toolchain.sh" --version v0.3.4
export CHIASMUS_VERSION=v0.3.4
"${PARITY_SKILL_DIR}/scripts/verify_skill_install.sh" . go tree-sitter
PORT_PARSER=tree-sitter make inventory
```

## Source of Truth

`vendor/rodney/` is a git submodule pointing to
`https://github.com/simonw/rodney` (release `v0.4.0`, commit `9e7ae93`). The Go
code in `vendor/rodney/main.go` defines the behavior contract. Crystal code must
produce the same outputs for the same inputs. The only allowed differences are:

- Crystal language idioms (method naming, type system, error handling)
- The documented divergences listed in `plans/parity.md`
  (**Intentional divergences**) and summarized in the README's
  **Differences from Rodney**:
  - `File.expand_path` for `webb file` upload paths (relative paths work)
  - a closed stdout exits 0 instead of finishing the command
  - the detached `_proxy` helper runs without `Setsid`
  - `--show` is accepted, `axtree`/`axfind`/`axnode` aliases exist

The ledger currently records **76 `ported`, 0 `partial`, 2
`intentional_divergence`** function rows; all 63 upstream tests are `ported`.

## Dir Layout

| Path | Purpose |
|---|---|
| `src/main.cr` | Entry point (SIGPIPE-tolerant `CLI.run` wrapper) |
| `src/webb.cr` | Core module: state, asserts, accessibility, downloads, proxy, OS errors |
| `src/cli.cr` | CLI command implementations |
| `src/test.cr` | Scratch entry that prints the `rod` shard version |
| `spec/webb_spec.cr` | Module specs: state, scope, caching, AX, asserts, downloads, uploads (100 examples) |
| `spec/cli_spec.cr` | CLI specs: process contract, `_proxy`, `start`, live browser (139 examples) |
| `spec/spec_helper.cr` | Test helper |
| `vendor/rodney/` | Go source of truth (git submodule) |
| `plans/parity.md` | Curated roadmap: **Where we are**, queue, divergences |
| `plans/history-*.md` | Completed work by area (CLI, ledger, shard pin) |
| `plans/inventory/` | Parity tracking TSV files |
| `CHANGELOG.md` | Release notes for user-visible changes (excluded from rumdl) |
| `scripts/` | Parity gate wrappers over the installed skill |
| `lib/` | Installed shard dependencies (gitignored) |
| `temp/` | Temporary files (gitignored) |

## Environment notes

This checkout lives on an exFAT volume, which has one real consequence: macOS
writes AppleDouble `._*` sidecars next to files, and a `._foo_spec.cr` sidecar
breaks Crystal spec discovery. `make format`, `make lint`, `make test`, and
`make clean` strip them first. Git pack operations can also print
`non-monotonic index .../._pack-*.idx`; delete those sidecars with
`find .git -name '._*' -delete`.

The spec suite launches a real headless Chrome. On a loaded machine (`uptime`
above ~20) the `waitstable` timing example, the `wait` late-element example, and
the `download`/`file` browser-parity examples can fail; re-run them in isolation
before treating a failure as a regression. A first `make test` can also lose
Chrome's debug-URL race and pass on the second run.
