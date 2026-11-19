# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated. Every checklist item
is one feature: one branch, one commit, one ledger update.
-->

## Where we are

- **Current focus:** reviewing Crystal mappings for the Go functions in the
  refreshed source manifest (Phase 2).
- **Next up:**
  1. Verify mappings for Go functions and any receiver methods in scope, then
     expand the curated ledger (Phase 2).
  2. Audit the three `partial` test rows against the current 64 Crystal specs
     and update statuses and references where the evidence supports it (Phase 2).
  3. Re-base the ledger when the pin moves off `v0.4.0` (Phase 2).
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 64 examples, 0 pending, 0 failures.
  - Curated ledger: 67 rows across 4 source declarations (`State` and 3
    scope constants) and 63 upstream tests. The ledger records 64 as `ported`
    and keeps `TestMain`, `TestFile_MultipleFiles`, and
    `TestFile_SetFileOnInput` marked `partial`.
  - Source manifest: 83 declarations at `v0.4.0` (1 class, 3 constants, 78
    functions, and 1 type). `State` keeps its reviewed mapping. The other
    rows, including `scopeMode`, are marked `missing` pending mapping review.
- **Scoping notes / gotchas:**
  - Discovery runs through the verified Chiasmus **tree-sitter** toolchain.
    Require `PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter` in each gate.
    Treat a reported `regex` backend as a failed gate.
  - The source manifest and curated ledger declare their kind scopes with
    `# kinds=`. The curated scope is `class,const,test`. The source manifest
    includes `main.go::type::scopeMode` from Chiasmus `v0.3.4`. Auxiliary
    facts such as `definition.type`, `definition.function`, and `reference.call`
    stay outside the source manifest.
  - The repo lives on an exFAT volume that grows AppleDouble `._*` sidecars;
    `._foo_spec.cr` breaks spec discovery. `make format|lint|test` and
    `make clean` strip them first.
  - Retained intentional divergence: HTTPS `CONNECT` proxying returns 501
    because Crystal's `HTTP::Server` cannot hijack the socket
    (`shard_issues/rod.001.md`, `src/cli.cr` proxy handler).
- **Last port commit:** `a729f6c` (`--insecure` over a self-signed HTTPS origin).
- **Gates (2026-11-18):** `make format`, `make lint` (5 files), `make test`
  (64 examples), and `make parity-verify` passed. `make inventory` passed with
  4 curated source rows, 83 source manifest rows, and 63 tests on
  `chiasmus-tree-sitter` with Chiasmus `v0.3.4`.

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
- [x] **Refresh Go source declaration discovery** — regenerate the source
      manifest against the pinned Go tree with the corrected skill, preserve
      the `State` mapping, and declare the curated ledger's existing kind
      scope explicitly.
- [x] **Discover Go named types** — Chiasmus `v0.3.4` adds exactly one
      source row for this pin, `main.go::type::scopeMode`. The curated ledger
      keeps its current kind scope pending review of the `Webb::ScopeMode`
      mapping.
- [ ] **Expand the ledger to Go function/method declarations** — review the
      pinned source manifest against the Crystal code and specs. Record
      statuses and real `crystal_refs` with the reviewed mappings, add the
      relevant kinds to the curated scope, and re-run `make inventory`.
- [ ] **Audit the three partial test rows** — compare the current Crystal specs
      with `TestMain`, `TestFile_MultipleFiles`, and `TestFile_SetFileOnInput`.
      Update the ledger entries with reviewed statuses and Crystal references.
- [ ] **Split the plan if it outgrows one screen** — move per-area detail into
      `plans/<area>.md`, link each file here, and mark it complete/in-progress.

## Done (no action)

Reference for what is already ported; do not re-open without a divergence:

- Test harness: Go `TestMain` (one headless Chrome + six fixture routes) is
  `AXSpecEnv` in `spec/webb_spec.cr`.
- Discovery: the parity gate runs on the chiasmus tree-sitter toolchain; the
  curated ledger uses tree-sitter IDs with explicit `class,const,test`
  coverage. The refreshed source manifest records discovery provenance in
  `.metadata.json`.
- File uploads: `TestFile_SetFileOnInput` and `TestFile_MultipleFiles` are the
  `.file browser parity` examples.
- AX tree/find/node, assert family, argument parsing, state-dir resolution,
  data-URL/download helpers, and scope flags: 60 ported test rows.
- `--insecure` over self-signed HTTPS: both upstream subtests are the
  `--insecure with a self-signed certificate` examples. The test manifest
  includes all 63 upstream tests.
- Exported Go API surface: `State` with matching JSON keys.

## Intentional divergences

- HTTPS `CONNECT` proxy: Crystal's `HTTP::Server` cannot hijack the socket, so
  proxy tunneling answers `501 Not Implemented` instead of tunneling
  (`shard_issues/rod.001.md`).
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case.
