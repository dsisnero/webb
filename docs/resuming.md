# Resuming Work

This is the first thing to read in a new session. It takes a few minutes to get
back to a known-good state.

## 1. Read where we are

- `plans/parity.md` — start at the **Where we are** block. It names the current
  focus, the ordered "Next up" list, per-area status, the last commit, and
  current gate results. There is no per-row queue left: every ledger row is
  `ported` or an `intentional_divergence`, and the next feature is whatever the
  next `vendor/rodney` pin adds (re-base the ledger first) or the optional
  real-HTTPS proxy example. Do not re-derive state from git history. Completed
  work is split out under `plans/history-*.md` (one file per area, linked from
  `parity.md`); open those only when changing behavior they describe.

- `plans/inventory/go_port_inventory.tsv` — the per-symbol ledger (status +
  `crystal_refs`), keyed to the baseline in its own leading `# baseline=`
  comment and re-based when the target release changes. Its `# kinds=` comment
  defines which declaration kinds must stay covered. Run `make inventory` to
  validate that scope and the referenced Crystal files. Check the current spread
  with:

  ```bash
  grep -v '^#' plans/inventory/go_port_inventory.tsv \
    | cut -f3 | sort | uniq -c
  ```

  The baseline records 76 `ported`, 0 `partial`, and 2 `intentional_divergence`.

- `plans/inventory/go_source_parity.tsv` — the source declarations discovered
  for the pin. `missing` rows are awaiting a reviewed Crystal mapping. Use this
  file to identify declarations to review before expanding the curated ledger's
  scope.

- `README.md` and `docs/*.md` — the user-facing contract. When behavior changes,
  update the examples there in the same commit; they are expected to be
  copy-paste accurate.

## 2. Confirm the working tree

```bash
git log --oneline -10
git status
```

The last commit should be the previous feature (`port: ...`) or its docs pointer
(`docs: ...`), committed atomically. If the tree is dirty, finish or stash
before starting.

## 3. Confirm a clean baseline

```bash
make format
make lint
make test
make build
make parity-verify
make docs-lint
PORT_PARSER=tree-sitter make inventory
```

Check lint, specs, the CLI build, and the inventory gate before changing
anything. Compare any drift with the **Where we are** block; recorded upstream
drift may be the next feature to fix. Confirm
`PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter` in each gate's output and the
same `backend` in the committed manifest metadata. The policy is recorded in
`AGENTS.md`.

Four examples are load-sensitive and can fail on a busy host, passing on a
re-run or in isolation: `waitstable`'s DOM-stability timing example, the `wait`
late-element example (its 2s reveal can beat a slow `open`), and the
`download`/`file` browser-parity examples. A first `make test` can also lose
Chrome's debug-URL race. Check `uptime` before treating one as a regression.

## 4. Pick the next feature

When the pin moves, the first job is always the ledger re-base:

1. Read the upstream source under `vendor/rodney` and the nearest upstream tests
   (`main.go`, `main_test.go`).
2. Re-base `plans/inventory/*.tsv` and the `# baseline=` headers in one commit
   before porting anything.
3. Port the tests first (red → green); never weaken assertions.
4. Satisfy the **Definition of done** in `AGENTS.md` (API, tests, gates,
   inventory rows, `plans/parity.md` status + **Where we are** refresh,
   divergences, README/docs examples).
5. Commit atomically with the `port: ...` message format from `AGENTS.md`.

## Environment notes

This checkout lives on an exFAT volume, which has one real consequence: macOS
writes AppleDouble `._*` sidecars next to files, and a `._foo_spec.cr` sidecar
breaks Crystal spec discovery. `make format`, `make lint`, `make test`, and
`make clean` strip them first. If a git pack operation prints
`non-monotonic index .../._pack-*.idx`, delete the sidecars with
`find .git -name '._*' -delete`.

File permissions are not enforced on this volume, so specs inject write failures
with a directory at the state path rather than `chmod` (see
`spec/webb_spec.cr .save_state`).
