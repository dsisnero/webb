# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated. Every checklist item
is one feature: one branch, one commit, one ledger update.
-->

## Where we are

- **Current focus:** expanding the ledger to Go function/method declarations
  now that discovery runs on tree-sitter (Phase 2).
- **Next up:**
  1. Expand the ledger to Go `function`/method declarations (Phase 2)
  2. Re-base the ledger when the pin moves off `v0.4.0` (Phase 2)
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 64 examples, 0 pending, 0 failures.
  - Ledger: 67 rows — 4 source declarations (`State` + 3 scope consts) and 63
    upstream tests; all `ported`.
- **Scoping notes / gotchas:**
  - Discovery runs through the verified chiasmus **tree-sitter** toolchain
    (`PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter`). A `regex` backend in the
    gate output is a silent fallback, not a pass.
  - The ledger's scope is the manifest declaration kinds (`class`, `const`)
    plus upstream tests. Tree-sitter also emits Go `function` facts, but the
    skill's curated Go filter drops the native `class`/`function` labels, so
    widening the ledger to functions is a reviewed migration (see Phase 2), not
    a flag flip.
  - The repo lives on an exFAT volume that grows AppleDouble `._*` sidecars;
    `._foo_spec.cr` breaks spec discovery. `make format|lint|test` and
    `make clean` strip them first.
  - Retained intentional divergence: HTTPS `CONNECT` proxying returns 501
    because Crystal's `HTTP::Server` cannot hijack the socket
    (`shard_issues/rod.001.md`, `src/cli.cr` proxy handler).
- **Last port commit:** `696f70c` (Update rod to 0.8.0, class-based `Cdp.call`)
- **Gates:** `make format` pass; `make lint` pass (5 files, 0 failures);
  `make test` pass (64 examples, 0 failures); `make inventory` pass
  (4 declarations, 63 tests, `chiasmus-tree-sitter` backend).

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

## Phase 1 — `--insecure` over self-signed HTTPS (done)

- [x] **`--insecure` end-to-end over self-signed HTTPS**
  - **Scope:** the CLI already parsed `--insecure`/`-k` and set
    `ignore-certificate-errors`; this feature ported the missing upstream test.
  - **Spec:** `--insecure with a self-signed certificate` — two examples
    mirroring the Go subtests: without the flag navigation raises a
    `Rod::NavigationError` mentioning `ERR_CERT_AUTHORITY_INVALID`; with the
    flag the page loads with title `Secure Test`.
  - **Fixture:** `InsecureTLSSpecEnv` binds `HTTP::Server` over TLS with a
    self-signed cert generated once into `temp/tls/`, and
    `launch_spec_browser(ignore_cert_errors:)` reuses the Go launcher flags.
  - **Ledger:** `TestInsecureFlag_WithSelfSignedCert` → `ported`.
  - **Red → green:** the first run failed with `undefined constant
    InsecureTLSSpecEnv`; the fixture landed next and the suite went green
    (64 examples, 0 failures). No product code changed — the ported behavior
    was already correct, the coverage was not.

## Phase 2 — Ledger and tooling hygiene

Each item is still one commit; none of them touch ported behavior.

- [ ] **Re-base the ledger on a pin change** — only when `vendor/rodney` moves
      off `v0.4.0`: rewrite the `# baseline=` header and rows for the new tag in
      one commit; never append across releases.
- [ ] **Expand the ledger to Go function/method declarations** — tree-sitter
      discovery already reports them; the skill's curated Go kind map drops the
      native labels, so this is a reviewed migration: regenerate into
      `temp/`, diff against the current rows, then add the `function`/`method`
      rows (status + real `crystal_refs`) in one commit and re-run the gate.
- [ ] **Split the plan if it outgrows one screen** — move per-area detail into
      `plans/<area>.md`, link each file here, and mark it complete/in-progress.

## Done (no action)

Reference for what is already ported; do not re-open without a divergence:

- Test harness: Go `TestMain` (one headless Chrome + six fixture routes) is
  `AXSpecEnv` in `spec/webb_spec.cr`.
- Discovery: the parity gate runs on the chiasmus tree-sitter toolchain; the
  ledger is re-based to tree-sitter IDs (`class`/`const` + tests) with
  `.metadata.json` provenance.
- File uploads: `TestFile_SetFileOnInput` and `TestFile_MultipleFiles` are the
  `.file browser parity` examples.
- AX tree/find/node, assert family, argument parsing, state-dir resolution,
  data-URL/download helpers, and scope flags: 60 ported test rows.
- `--insecure` over self-signed HTTPS: both upstream subtests are the
  `--insecure with a self-signed certificate` examples; the whole upstream test
  suite (63 tests) is now `ported`.
- Exported Go API surface: `State` with matching JSON keys.

## Intentional divergences

- HTTPS `CONNECT` proxy: Crystal's `HTTP::Server` cannot hijack the socket, so
  proxy tunneling answers `501 Not Implemented` instead of tunneling
  (`shard_issues/rod.001.md`).
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case.
