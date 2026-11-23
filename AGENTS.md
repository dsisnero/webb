# webb

> **How to resume:** read `plans/parity.md` first and use its **Where we are**
> block (current focus + ordered "Next up"), then run `make lint` and
> `make test`. Details: [docs/resuming.md](docs/resuming.md). Do not re-derive
> state from git.

Crystal port of rodney (Go) from
[simonw/rodney](https://github.com/simonw/rodney), vendored at `vendor/rodney`
(release `v0.4.0`, commit `9e7ae93900bcb5316d02623706bc8861feec836f`).

Upstream behavior is the contract: all logic must match the Go implementation,
differing only in Crystal idioms and libraries. Port all Go code and Go tests.

## Commands

```bash
make install        # shards install
make update         # shards update
make format         # crystal tool format --check
make lint           # ameba --fix, then ameba
make test           # crystal spec
make build          # compile the CLI entry point to bin/webb
make inventory      # tree-sitter parity gates against vendor/rodney
make parity-verify  # verify the installed parity skill + discovery backend
make docs-lint      # rumdl check README.md docs/ (skipped when rumdl is absent)
make clean          # remove temp/ contents and AppleDouble sidecars
```

## Docs

- [README](README.md) — usage, examples, checks, divergences
- [Resuming work](docs/resuming.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Coding Guidelines](docs/coding-guidelines.md)
- [Testing](docs/testing.md)
- [PR Workflow](docs/pr-workflow.md)
- [Changelog](CHANGELOG.md) — release notes; add an entry for cross-cutting
  changes (new commands or flags, shard pin moves, divergence changes)

## Principles

1. Upstream behavior is the source of truth; `vendor/rodney` wins over local
   preference.
2. Port behavior, not style.
3. Port upstream tests early and never weaken assertions.
4. Track parity in `plans/parity.md` and `plans/inventory/`.
5. Commit one completed feature at a time.

## Parity tooling

The active cross-language parity skill is
`/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity`.
Run its current `scripts/` directly; `make inventory` must invoke those scripts
or a thin forwarding wrapper, never a copied parity implementation. The scripts
in `scripts/` are forwarding wrappers (see `scripts/parity_skill_lib.sh`) and
resolve the skill from `PARITY_SKILL_DIR` (default: the path above). Check the
command's target when first adopting this skill or when inventory behavior
changes. Updating the installed skill does not update copied repository scripts.

The parity gates use **tree-sitter** (`PARITY_PARSER=tree-sitter` in the
`Makefile`). Require `PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter` in the
output. Treat a reported `regex` backend as a failed gate. Before relying on
discovery, run:

```bash
PARITY_SKILL_DIR="${HOME}/.agents/skills/crystal_forge/skills/cross-language-crystal-parity"
"${PARITY_SKILL_DIR}/scripts/install_chiasmus_toolchain.sh" --version v0.3.4
export CHIASMUS_VERSION=v0.3.4
"${PARITY_SKILL_DIR}/scripts/verify_skill_install.sh" . go tree-sitter
PORT_PARSER=tree-sitter make inventory
```

`go_source_parity.tsv` records the pinned source declarations discovered under
its `# kinds=` scope. The scope includes `function`, `method`, `interface`, and
`type`. Chiasmus `v0.3.4` emits the `type` ID for `scopeMode`.
The curated `go_port_inventory.tsv` declares
`# kinds=class,const,function,method,test,type` and records Crystal port status
for that scope. When signing off a function or method, update its status and
`crystal_refs` with evidence from the implementation and specs. The generated
source manifest records discovery separately.

Check `PARITY_DISCOVERY_BACKEND` in the gate output and `backend` in the
committed `plans/inventory/*.metadata.json` files. A requested parser mode or an
installed Ruby gem does not prove tree-sitter ran. Chiasmus binary releases are
resolved by the installed skill; they are distinct from the skill scripts.

## Session continuity (read this first)

`plans/parity.md` is the single source of truth for where we are. At the start
of every session:

1. Read `plans/parity.md` and use its **Where we are** block to find the current
   focus, the ordered "Next up" list, and per-area chunk status. Do not
   re-derive state from git history.
2. Skim `git log --oneline -10` and `git status` to confirm the working tree.
3. Confirm the **Parity tooling** command uses the installed skill scripts and
   the ledger's parser mode, then run `make lint`, `make test`, and
   `make inventory` before changes.

See [docs/resuming.md](docs/resuming.md) for the full resume checklist.

### Keeping `plans/parity.md` resumable

- `plans/parity.md` starts with a **Where we are** block (`Current focus`,
  `Next up`, chunk status by area). Keep it accurate after every feature.
- Work items are feature-sized (roughly one branch/commit). Per-symbol state
  lives in `plans/inventory/go_port_inventory.tsv`, not in the plan.
- The ledger is a **current-state** artifact of the pinned baseline (say so in
  its leading `# baseline=` comment). Re-base it when the target release
  changes; never append across versions. Keep its `# kinds=` declaration
  explicit so losing the final row of a kind still fails the gate.
- If `plans/parity.md` grows too large, split it into `plans/<area>.md` files,
  link each from `plans/parity.md`, and mark each split file
  complete/in-progress plus the file being worked on next.

### Definition of done for every feature (required)

A feature is complete only when all of the following are true, and all of it
must be committed as **one** atomic commit before starting the next feature:

1. the API surface is implemented;
2. upstream tests (or equivalent characterization specs) exist and pass;
3. gates pass: `make format`, `make lint`, `make test`, `make build`,
   `make inventory`, and `make parity-verify`;
4. parity inventory rows for the feature are updated
   (`plans/inventory/go_port_inventory.tsv`) and `make inventory` passes — it
   checks every row against the pinned tree *and* that each `crystal_refs` file
   still exists, which is the half that rots when this repo's own files move;
5. `plans/parity.md` status is updated and the **Where we are** block refreshed
   (current focus + next up);
6. any intentional divergence is documented (in `plans/parity.md` and/or the
   commit message);
7. user-facing docs keep up: when output, flags, or behavior change, update the
   examples in `README.md` and the affected `docs/*.md`, add an entry to
   `CHANGELOG.md`, and keep them verified against the built CLI
   (`rumdl check README.md docs/` is clean).

### Commit message

Start with `port:` and a one-line feature name, then bullets for what changed,
then the upstream revision (`simonw/rodney v0.4.0 (9e7ae93)`). Include
new/changed files, divergences, and the gate results so a new session can
resume from the commit alone.

## Landing the plane (session completion)

**When ending a work session**, complete ALL steps below. Work is NOT complete
until `git push` succeeds.

1. **Record remaining work** — add unchecked items to `plans/parity.md` for
   anything that needs follow-up.
2. **Run quality gates** — `make format`, `make lint`, `make test`,
   `make build`, `make inventory`. No formatting issues, no ameba failures, all specs green.
3. **Update plan status** — tick finished items and refresh **Where we are**.
4. **Push to remote** — mandatory:

   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** — clear stashes, prune remote branches.
6. **Verify** — all changes committed AND pushed.
7. **Hand off** — provide context for the next session.

**Critical rules:**

- Work is NOT complete until `git push` succeeds.
- NEVER stop before pushing — that strands work locally.
- NEVER say "ready to push when you are" — YOU must push.
- If push fails, resolve and retry until it succeeds.

## Crystal development guidelines

- Use Crystal's built-in formatter: `crystal tool format`.
- Use ameba for linting: `ameba --fix`, then `ameba` to verify.
- Prefer Crystal's standard library over custom implementations.
- Use Crystal's type system effectively (avoid unnecessary `as` casts).
- Follow Crystal naming conventions (snake_case for methods/variables,
  CamelCase for classes).
- Write specs for new functionality using Crystal's built-in spec framework.

### Test porting guidelines

When porting Go tests to Crystal specs:

1. **Port test logic exactly** — don't adjust assertions or expected values.
2. **Use Crystal idioms for structure** — convert Go test tables to Crystal
   `it` blocks.
3. **Mark missing functionality as pending** — use `pending` only when a test
   genuinely cannot run yet, and reference the blocking shard issue.
4. **Follow Go test patterns** — keep the same coverage and edge cases.
5. **Verify against Go** — Crystal behavior must match Go exactly.

## File system guidelines

- Use `./temp` for temporary files created during testing or development.
- Never commit temporary files (they are gitignored).
- Clean up after use: `make clean` empties `./temp` and removes AppleDouble
  sidecars.
- This volume is exFAT: macOS writes `._*` sidecars, and a `._foo_spec.cr`
  breaks spec discovery. `make format|lint|test` strip them first.
