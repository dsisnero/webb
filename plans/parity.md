# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated. Every checklist item
is one feature: one branch, one commit, one ledger update.
-->

## Where we are

- **Current focus:** closing `partial` function rows against the live-browser
  CLI harness; the `cmd_wait_stable` duration is next.
- **Next up:**
  1. Align `cmd_wait_stable` with Go's `MustWaitStable()` (`WaitStable(1s)`):
     assert `DOM stable` on stdout and an elapsed time near one second through
     the browser-backed harness, and fix the `100.milliseconds` call.
  2. Characterize `getActivePage` on an empty browser and reconcile the
     behavior of `withPage` and `open` with the pinned Go implementation.
  3. Work through remaining partial function rows in feature-sized changes,
     starting with the rows that carry a concrete divergence note
     (`cmdConnect`, `cmdSelect`, `cmdSubmit`, `cmdScreenshot`, `cmdSleep`,
     `cmdStart`, `cmdStop`).
  4. Re-base the ledger when the pin moves off `v0.4.0` (Phase 2).
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 64 examples. `spec/cli_spec.cr`: 10 examples; 7 run
    the CLI as a process, 3 drive it against a live headless Chrome through a
    temp `state.json`. Suite total: 74 examples, 0 pending, 0 failures.
  - Curated ledger: 145 rows across 82 source declarations and 63 upstream
    tests. All 78 function IDs have Crystal references: 17 are `ported`, 59
    `partial`, and 2 `intentional_divergence`. The pin has no receiver method
    IDs. All 63 upstream test rows are `ported`; no test row is `partial`.
  - Source manifest: 83 declarations at `v0.4.0` (1 class, 3 constants, 78
    functions, and 1 type). Implementation statuses are in the curated
    ledger. The generated source snapshot keeps its discovery baseline
    statuses; `scopeMode` still needs a curated type mapping.
- **Scoping notes / gotchas:**
  - Discovery runs through the verified Chiasmus **tree-sitter** toolchain.
    Require `PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter` in each gate.
    Treat a reported `regex` backend as a failed gate.
  - The source manifest and curated ledger declare their kind scopes with
    `# kinds=`. The curated scope is `class,const,function,method,test`.
    The source manifest includes `main.go::type::scopeMode` from Chiasmus `v0.3.4`.
    Auxiliary facts such as `definition.type`, `definition.function`, and `reference.call`
    stay outside the source manifest.
  - The repo lives on an exFAT volume that grows AppleDouble `._*` sidecars;
    `._foo_spec.cr` breaks spec discovery. `make format|lint|test` and
    `make clean` strip them first.
  - Retained intentional divergence: HTTPS `CONNECT` proxying returns 501
    because Crystal's `HTTP::Server` cannot hijack the socket
    (`shard_issues/rod.001.md`, `src/cli.cr` proxy handler).
- **Last port commit:** `port: add a browser-backed CLI harness` (see
  `git log -1 --oneline`).
- **Gates (2026-11-18):** `make format`, `make lint` (5 files), `make test`
  (74 examples), `make build` (CLI), and `make parity-verify` passed.
  `make inventory` passed with 82 curated source rows, 83 source manifest
  rows, and 63 tests on
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

Each item is scoped to a single commit. See the entries below for verification details.

- [ ] **Re-base the ledger on a pin change** — only when `vendor/rodney` moves
      off `v0.4.0`: rewrite the `# baseline=` header and rows for the new tag in
      one commit; never append across releases.
- [x] **Refresh Go source declaration discovery** — regenerate the source
      manifest against the pinned Go tree with the corrected skill, preserve
      the `State` mapping, and declare the curated ledger's existing kind
      scope explicitly.
- [x] **Discover Go named types** — Chiasmus `v0.3.4` adds exactly one
      source row for this pin, `main.go::type::scopeMode`. The curated ledger
      keeps type coverage out of scope pending review of `Webb::ScopeMode`.
- [x] **Expand the ledger to Go function/method declarations** — declaring
      the wider scope first failed strict tree-sitter inventory with 78
      missing functions. Mapping all 78 to Crystal symbols made the same
      gate pass. The existing 67 curated rows were preserved. Partial rows
      identify behavior differences or missing evidence. Both Go
      `init` functions share a single discovery ID; timeout initialization
      is mapped and SIGPIPE behavior is still open. The Windows Go process
      helper is a no-op and has no separate Crystal counterpart. Building the
      actual CLI also caught the invalid PID constructor in `stop`. The build
      now targets `src/main.cr`, and the repaired `stop` sent TERM to two
      disposable processes and removed its state file in a CLI smoke check.
- [x] **Audit the three partial test rows** — every row had working Crystal
      coverage; the ledger was stale, and one spec drifted from upstream.
      - `TestMain` → `ported` (`spec/webb_spec.cr::AXSpecEnv`): same launcher
        flags, `ROD_CHROME_BIN` override, and the six fixture routes, created in
        `before_all` and closed in `after_all`. Divergences: Crystal also kills
        the launcher and falls back to a local Chrome path.
      - `TestFile_SetFileOnInput` → `ported`: assertions match Go. The spec now
        waits `1.second` to mirror `MustWaitStable()` =
        `WaitStable(time.Second)` (it drifted to 100 ms) and removes its temp
        file in `ensure`, as Go does with `defer os.Remove`.
      - `TestFile_MultipleFiles` → `ported`: same `set_files` call with no
        post-condition beyond not raising; both temp files are now removed.
      - Discovery: `plans/inventory/go_test_parity.tsv` already recorded all
        three as `ported`; only the curated ledger still said `partial`.
- [x] **Add a CLI process output harness** — `spec/cli_spec.cr` builds the CLI
      into `temp/cli_spec/webb`, runs it with a scrubbed environment
      (`HOME`/`RODNEY_HOME` under `temp/`), and asserts stdout, stderr, and exit
      status together. The first coverage found three real bugs:
      - an unknown command printed `error: unknown command: ...` on stderr and
        no usage, where Go prints the bare line on stderr plus usage on stdout
        with exit 2;
      - the usage advertised `./.webb/` and `~/.webb/` while the code and docs
        use `.rodney`;
      - the `Use "webb start --local"` hint was missing.
      The usage is now byte-equal to `vendor/rodney/help.txt` after the `webb`
      rename, plus the two env knobs the port really reads, and a spec compares
      the full text so future command changes cannot drift silently. Ledger:
      `main` and `printUsage` → `ported`.
- [x] **Add a browser-backed CLI harness** — `CLISpecHarness` now launches one
      headless Chrome with the same flags as `AXSpecEnv`, serves a fixture page
      from an in-process `HTTP::Server`, and writes a `state.json` with the
      launcher's debug URL and PID into `temp/cli_spec/browser_home`. `run_cli_live`
      points the CLI there, so a `cmd*` function can be asserted end to end.
      - Coverage added: `open` navigates the fixture and prints its title,
        `title` and `url` read the active page, and an empty state directory
        yields Go's `no browser session` error with exit 2.
      - Evidence only; every touched ledger row stays `partial` because the
        `page.info` error paths still differ from Go's fatals.
      - The harness kills its launcher and server in `after_all`; a run leaves
        no Chrome behind (checked with `ps`).
- [ ] **Align `cmd_wait_stable` with Go's `MustWaitStable()`** — `src/cli.cr`
      passes `100.milliseconds` where Go waits `time.Second`; assert `DOM
      stable` and an elapsed time near one second through the browser-backed
      harness, then fix the call.
- [ ] **Split the plan if it outgrows one screen** — move per-area detail into
      `plans/<area>.md`, link each file here, and mark it complete/in-progress.

## Done (no action)

Reference for what is already ported; do not re-open without a divergence:

- Test harness: Go `TestMain` (one headless Chrome + six fixture routes) is
  `AXSpecEnv` in `spec/webb_spec.cr`.
- Discovery: the parity gate runs on the chiasmus tree-sitter toolchain; the
  curated ledger uses tree-sitter IDs with an explicit kind scope. The source
  manifest records discovery provenance in `.metadata.json`.
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
- CLI usage text is `webb`-branded and adds `ROD_CHROME_BIN` and `ROD_TIMEOUT`
  to upstream's `help.txt`; both are env knobs the port really reads. Everything
  else in the output is upstream text verbatim, and `spec/cli_spec.cr` compares
  the whole block.
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case.
