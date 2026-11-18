# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated.
-->

## Where we are

- **Current focus:** closing the four `partial` rows in the parity ledger —
  browser-dependent behaviors that depend on the `rod` shard (file upload
  inputs, HTTPS with a self-signed cert) and the CLI-level `TestMain` harness.
- **Next up:**
  1. Port `main_test.go::TestFile_MultipleFiles` and
     `main_test.go::TestFile_SetFileOnInput` once `lib/rod` supports setting
     files on `<input type="file">`.
  2. Port `main_test.go::TestInsecureFlag_WithSelfSignedCert` (needs the
     self-signed-cert proxy/ignore-TLS path to be exercised end-to-end).
  3. Port `main_test.go::TestMain` (CLI entrypoint harness: arg parsing, exit
     codes, `--help` output against `vendor/rodney/help.txt`).
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported; 60/64
    ledger rows `ported`.
  - `src/cli.cr` (command implementations): ported command-by-command; the
    CLI harness itself is the remaining test gap.
  - `spec/webb_spec.cr`: 62 examples, 0 pending, 0 failures.
  - Exported Go API surface: `State` mapped in `go_source_parity.tsv`.
- **Scoping notes / gotchas:**
  - The ledger is **regex-derived** (`parser=regex`). Discovery surfaces the
    exported Go API plus upstream tests only; unexported helpers are not rows.
    Do not switch the gate to `tree-sitter` without a reviewed manifest
    regeneration and an `AGENTS.md` policy update.
  - `bd` (beads) is currently unusable in this checkout: the Dolt server
    reports `database "webb" not found` and `bd bootstrap` fails with
    `dolt commit: nothing to commit`. The volume is exFAT, where Dolt's backup
    hardlink also fails (`operation not supported`). Issue state is still
    recoverable from the git-tracked `.beads/issues.jsonl` (3 issues). See
    `docs/resuming.md` → Environment notes before trying to repair it.
  - The repo lives on an exFAT volume that grows AppleDouble `._*` sidecars;
    `._foo_spec.cr` breaks spec discovery. `make format|lint|test` and
    `make clean` strip them first.
  - Retained intentional divergence: HTTPS `CONNECT` proxying returns 501
    because Crystal's `HTTP::Server` cannot hijack the socket
    (`shard_issues/rod.001.md`, `src/cli.cr` proxy handler).
- **Last commit:** `696f70c` (Update rod to 0.8.0, class-based `Cdp.call`)
- **Gates:** `make format` pass; `make lint` pass (5 files, 0 failures);
  `make test` pass (62 examples, 0 failures); `make inventory` pass
  (1 API item, 63 tests, regex backend).

Keep this block accurate after every feature: the next session reads it first
(see `AGENTS.md` → **How to resume**).

## Phase 1 — Browser-dependent parity (open)

- [ ] `TestFile_MultipleFiles`: multiple file inputs on one form
- [ ] `TestFile_SetFileOnInput`: file input requires `lib/rod` support
- [ ] `TestInsecureFlag_WithSelfSignedCert`: `--insecure` against a
      self-signed HTTPS origin
- [ ] `TestMain`: CLI harness (arg parsing, exit codes, `help.txt` parity)

## Phase 2 — Ledger hygiene (open)

- [ ] Re-base `plans/inventory/*.tsv` only when the pin moves off `v0.4.0`
- [ ] Re-evaluate native `tree-sitter` discovery as a separate change; keep the
      curated `regex` gate authoritative until then
- [ ] Restore `bd` on a non-exFAT data directory so issue tracking works again

## Intentional divergences

- HTTPS `CONNECT` proxy: Crystal's `HTTP::Server` cannot hijack the socket, so
  proxy tunneling answers `501 Not Implemented` instead of tunneling
  (`shard_issues/rod.001.md`).
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case.
