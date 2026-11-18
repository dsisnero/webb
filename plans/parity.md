# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated. Every checklist item
is one feature: one branch, one commit, one ledger update.
-->

## Where we are

- **Current focus:** the single remaining parity gap — `--insecure` end-to-end
  against a self-signed HTTPS origin (Phase 1).
- **Next up:**
  1. Port `main_test.go::TestInsecureFlag_WithSelfSignedCert` (Phase 1)
  2. Re-base the ledger when the pin moves off `v0.4.0` (Phase 2)
  3. Evaluate native `tree-sitter` discovery as a spike (Phase 2)
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command;
    `--insecure` parses and sets `ignore-certificate-errors`, but has no
    end-to-end spec yet.
  - `spec/webb_spec.cr`: 62 examples, 0 pending, 0 failures.
  - Ledger: 63/64 rows `ported`, 1 `partial`
    (`TestInsecureFlag_WithSelfSignedCert`). Exported Go API (`State`) mapped.
- **Scoping notes / gotchas:**
  - The ledger is **regex-derived** (`parser=regex`). Discovery surfaces the
    exported Go API plus upstream tests only; unexported helpers are not rows.
    Do not switch the gate to `tree-sitter` without a reviewed manifest
    regeneration and an `AGENTS.md` policy update.
  - The repo lives on an exFAT volume that grows AppleDouble `._*` sidecars;
    `._foo_spec.cr` breaks spec discovery. `make format|lint|test` and
    `make clean` strip them first.
  - Retained intentional divergence: HTTPS `CONNECT` proxying returns 501
    because Crystal's `HTTP::Server` cannot hijack the socket
    (`shard_issues/rod.001.md`, `src/cli.cr` proxy handler).
- **Last port commit:** `696f70c` (Update rod to 0.8.0, class-based `Cdp.call`)
- **Gates:** `make format` pass; `make lint` pass (5 files, 0 failures);
  `make test` pass (62 examples, 0 failures); `make inventory` pass
  (1 API item, 63 tests, regex backend).

Keep this block accurate after every feature: the next session reads it first
(see `AGENTS.md` → **How to resume**).

## How features are sliced

Each checklist item below is **one feature = one commit**, sized so it:

1. changes one behavior area only — one CLI flag, one command, one harness
   piece, one ledger migration;
2. lands its spec in the same commit (red → green), never after;
3. updates the ledger rows for that behavior only, then runs `make inventory`;
4. stays reviewable in one sitting and revertible on its own.

If an item needs a second area, split it into two items instead of widening it.
Do not batch items: a commit that closes two checkboxes is two features.

## Phase 1 — Remaining parity feature (`--insecure`)

One feature, one commit.

- [ ] **`--insecure` end-to-end over self-signed HTTPS**
  - **Scope:** CLI parsing and the launcher option already exist
    (`--insecure`/`-k` → `ignore-certificate-errors`). The missing piece is the
    upstream test port.
  - **Spec:** two examples mirroring the Go subtests:
    - without the flag: navigation fails and the error mentions
      `ERR_CERT_AUTHORITY_INVALID`;
    - with the flag: the page loads and its title is `Secure Test`.
  - **Fixture:** HTTPS mirror of `AXSpecEnv` supplying the same HTML body;
    generate the self-signed cert once into `temp/`, and discard TLS handshake
    noise the way the Go test discards its `ErrorLog`.
  - **Ledger:** `TestInsecureFlag_WithSelfSignedCert` → `ported` with a
    `spec/webb_spec.cr` ref; this closes the last `partial` row.
  - **Gates:** `make format`, `make lint`, `make test`, `make inventory`.

## Phase 2 — Ledger and tooling hygiene

Each item is still one commit; none of them touch ported behavior.

- [ ] **Re-base the ledger on a pin change** — only when `vendor/rodney` moves
      off `v0.4.0`: rewrite the `# baseline=` header and rows for the new tag in
      one commit; never append across releases.
- [ ] **Evaluate native `tree-sitter` discovery** — spike only: compare
      discovered IDs with the curated regex ledger, report drift, and keep the
      `regex` gate authoritative until a reviewed manifest migration lands.
- [ ] **Split the plan if it outgrows one screen** — move per-area detail into
      `plans/<area>.md`, link each file here, and mark it complete/in-progress.

## Done (no action)

Reference for what is already ported; do not re-open without a divergence:

- Test harness: Go `TestMain` (one headless Chrome + six fixture routes) is
  `AXSpecEnv` in `spec/webb_spec.cr`.
- File uploads: `TestFile_SetFileOnInput` and `TestFile_MultipleFiles` are the
  `.file browser parity` examples.
- AX tree/find/node, assert family, argument parsing, state-dir resolution,
  data-URL/download helpers, and scope flags: 60 ported test rows.
- Exported Go API surface: `State` with matching JSON keys.

## Intentional divergences

- HTTPS `CONNECT` proxy: Crystal's `HTTP::Server` cannot hijack the socket, so
  proxy tunneling answers `501 Not Implemented` instead of tunneling
  (`shard_issues/rod.001.md`).
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case.
