# Development

## Quick Reference

```bash
make install   # Install shards (with BEADS_DIR set)
make build     # Compile binary to bin/webb
make format    # Check formatting (crystal tool format --check)
make lint      # Lint and auto-fix (ameba --fix, then ameba)
make test      # Run specs (crystal spec)
make inventory # Parity ledger gate (regex backend, vendor/rodney)
make clean     # Remove temp/ contents and AppleDouble sidecars
```

## Dependency: `rod` Crystal Shard

This project depends on the `rod` Crystal shard (`github: dsisnero/rod`), a port of
`go-rod/rod`. The shard is declared in `shard.yml` and installed under `lib/rod/`.

The shard source at `lib/rod/` may contain patches that fix parity issues. Any deliberate
divergence from upstream rod should be documented in `shard_issues/` with a reproducible
test case and upstream follow-up issue.

## Porting Workflow

1. **Reference the Go source**: Find the function/test in `vendor/rodney/main.go` or
   `vendor/rodney/main_test.go`
2. **Check parity inventory**: `plans/inventory/go_port_inventory.tsv` tracks port status
   for every Go construct
3. **Translate to Crystal**: Preserve behavior exactly; use Crystal idioms (snake_case
   methods, `case`/`when`, Crystal's `JSON.mapping`, etc.)
4. **Port corresponding tests**: Create Crystal spec in `spec/webb_spec.cr` that mirrors
   the Go test logic
5. **Run quality gates**: `make format && make lint && make test && make inventory`
6. **Update the ledger**: mark items as `ported` in
   `plans/inventory/go_port_inventory.tsv`, refresh `plans/parity.md`'s
   **Where we are** block, and re-run `make inventory`

## Parity Tooling

The parity gate is not implemented in this repo. `scripts/*.sh` are thin
forwarding wrappers around the installed cross-language parity skill
(`PARITY_SKILL_DIR`, default
`~/.agents/skills/crystal_forge/skills/cross-language-crystal-parity`); update
the skill, not the wrappers, when gate behavior changes. Never copy the skill's
Ruby helpers back into `scripts/`.

The curated ledger is regex-derived (`parser=regex`), matching the
`# baseline=` header of each manifest and the policy recorded in `AGENTS.md`.
`make inventory` runs all three checks (port inventory, source parity, test
parity) against `vendor/rodney`; `make parity-verify` checks the installed
skill and reports `PARITY_DISCOVERY_BACKEND`.

## Issue Tracking with `bd`

```bash
bd ready              # Find unblocked work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

See `AGENTS.md` for the full bd workflow.

## Source of Truth

`vendor/rodney/` is a git submodule pointing to `https://github.com/simonw/rodney`.
The Go code in `vendor/rodney/main.go` defines the behavior contract. Crystal code must
produce the same outputs for the same inputs. The only allowed differences are:

- Crystal language idioms (method naming, type system, error handling)
- Documented intentional deviations (e.g., HTTPS CONNECT proxy limitation at
  `src/cli.cr:1037`)

## Dir Layout

| Path | Purpose |
|---|---|
| `src/main.cr` | Entry point |
| `src/webb.cr` | Core module: state, asserts, accessibility, downloads |
| `src/cli.cr` | CLI command implementations |
| `spec/webb_spec.cr` | All specs (~853 lines, 50+ test cases) |
| `spec/spec_helper.cr` | Test helper |
| `vendor/rodney/` | Go source of truth (git submodule) |
| `plans/parity.md` | Curated parity roadmap (**Where we are**) |
| `plans/inventory/` | Parity tracking TSV files |
| `scripts/` | Parity gate wrappers over the installed skill, bd/inventory helpers |
| `lib/` | Installed shard dependencies (gitignored) |
| `temp/` | Temporary files (gitignored) |
