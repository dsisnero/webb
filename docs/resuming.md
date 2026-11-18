# Resuming Work

This is the first thing to read in a new session. It takes a few minutes to get
back to a known-good state.

## 1. Read where we are

- `plans/parity.md` — start at the **Where we are** block. It names the current
  focus, the ordered "Next up" list, per-area chunk status, and any scoping
  notes or gotchas, plus the last commit and current gate results. Do not
  re-derive state from git history.
- `plans/inventory/go_port_inventory.tsv` — the per-symbol ledger (status +
  `crystal_refs`), keyed to the baseline in its own leading `# baseline=`
  comment and re-based when the target release changes. Run `make inventory`
  before trusting it: it fails on a stale row and on a `crystal_refs` file that
  no longer exists. Use it to see what is left inside the current chunk:

  ```bash
  grep -v '^#' plans/inventory/go_port_inventory.tsv \
    | cut -f3 | sort | uniq -c
  ```

## 2. Confirm the working tree

```bash
git log --oneline -10
git status
```

The last commit should be the previous feature (`port: ...`), committed
atomically. If the tree is dirty, finish or stash before starting.

## 3. Confirm a clean baseline

```bash
make format
make lint
make test
PARITY_SKILL_DIR="${HOME}/.agents/skills/crystal_forge/skills/cross-language-crystal-parity"
"${PARITY_SKILL_DIR}/scripts/verify_skill_install.sh" . go regex
make inventory
```

Lint and tests must pass before changing anything. Run the inventory gate
and compare any drift with the **Where we are** block; recorded upstream drift
may be the next feature to fix. Confirm `PARITY_DISCOVERY_BACKEND=regex` in the
gate output; the curated ledger is regex-derived and that is the policy recorded
in `AGENTS.md`.

## 4. Pick the next feature

Take the first unchecked item in the **Next up** list (or the next `[ ]` item in
the current phase). For each feature:

1. Read the upstream source under `vendor/rodney` and the nearest upstream
   tests (`main.go`, `main_test.go`).
2. Port the tests first (red → green); never weaken assertions.
3. Satisfy the **Definition of done** in `AGENTS.md` (API, tests, gates,
   inventory rows, `plans/parity.md` status + **Where we are** refresh,
   divergences).
4. Commit atomically with the `port: ...` message format from `AGENTS.md`.

## Environment notes

This checkout lives on an exFAT volume, which has two real consequences:

- **AppleDouble sidecars.** macOS writes `._*` sidecars next to files; a
  `._foo_spec.cr` sidecar breaks Crystal spec discovery. `make format`,
  `make lint`, `make test` and `make clean` strip them first. If a git pack
  operation prints `non-monotonic index .../._pack-*.idx`, delete the sidecars
  with `find .git -name '._*' -delete`.
- **`bd` (beads/Dolt) is currently unusable here.** `bd ready` fails with
  `database "webb" not found`, `bd bootstrap` ends in
  `dolt commit: nothing to commit`, and Dolt's auto-backup cannot create its
  hardlinks (`operation not supported`). Do not run `bd bootstrap` or
  `bd import` as a quick fix: both have consumed the git-tracked
  `.beads/issues.jsonl`, so restore it with
  `git checkout -- .beads/issues.jsonl` before doing anything else. The JSONL
  is the durable issue record until the Dolt data directory lives on a
  hardlink-capable filesystem (e.g. APFS).
