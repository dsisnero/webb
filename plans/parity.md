# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated. Every checklist item
is one feature: one branch, one commit, one ledger update.

This file is the session entry point. Completed work lives in `plans/history-*.md`
(see **History** at the bottom); it is only needed when changing behavior
described there.
-->

## Where we are

- **Current focus:** slice the remaining 27 `partial` ledger rows. Every
  *documented* divergence is closed — `start`, `stop`, `connect`, `status`,
  `attr`, `assert`, the element checks, the AX commands, `waitstable`, the
  `_proxy` helper, the page-info error contract (`title`, `url`), the whole tab
  family (`pages`, `page`, `newpage`, `closepage`), `back`, `forward`, and
  `reload` all match Go, and `shard_issues/` is empty.
- **Next up:**
  1. **`cmdClearCache`** (details below) — `clear cache failed: <cause>`, one
     commit.
  2. Then page content
     (`cmdHTML`, `cmdText`, `cmdJS`), interaction (`cmdClick`, `cmdInput`,
     `cmdClear`, `cmdHover`, `cmdFocus`), files (`cmdPDF`, `cmdDownload`,
     `cmdFile`), and waits (`cmdWait`, `cmdWaitLoad`, `cmdWaitIdle`,
     `cmdScreenshotEl`).
  3. **Helper rows with no CLI surface** — `formatAXNodeList`,
     `formatAXNodeDetail`, `formatProperties`, `detectProxy`, `nextAvailableFile`,
     `connectBrowser`, `loadState`, `saveState`, `removeState`, `init`, and
     `proc_unix.go::setSysProcAttr`. Most need unit specs in `webb_spec.cr`
     (`axValueStr`, `page_info`, `page_info?`), not CLI examples.
  4. **Re-base the ledger** when `vendor/rodney` moves off `v0.4.0`.
  5. **Optional:** a Chrome-through-the-proxy example against a real HTTPS
     origin; today `_proxy` is proven at the socket level.
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 72 examples. `spec/cli_spec.cr`: 86 examples (22
    process-contract, 3 `_proxy`, 4 `start` session, 57 live-browser). Suite
    total: 158 examples, 0 pending, 0 failures.
  - Curated ledger: 145 rows across 82 source declarations and 63 upstream
    tests. All 78 function IDs have Crystal references: **49 `ported`, 27
    `partial`, 2 `intentional_divergence`**. The pin has no receiver method IDs.
    All 63 upstream test rows are `ported`; no test row is `partial`.
  - Source manifest: 83 declarations at `v0.4.0` (1 class, 3 constants, 78
    functions, 1 type). Implementation statuses live in the curated ledger;
    `scopeMode` still needs a curated type mapping.
  - CLI harness: `spec/cli_spec.cr` builds `src/main.cr` into
    `temp/cli_spec/webb` once. `run_cli` uses an empty `RODNEY_HOME`;
    `run_cli_live` points at `browser_home/state.json`; `state_home`,
    `raw_state_home`, `session_home`, and `owned_browser` set up `stop`,
    `start`, and status scenarios. Chrome runs with `--no-startup-window`, so a
    fresh browser has **zero pages**.
- **Scoping notes / gotchas:**
  - Discovery runs through the verified Chiasmus **tree-sitter** toolchain.
    Require `PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter` in each gate; treat
    a reported `regex` backend as a failed gate.
  - The source manifest and curated ledger declare their kind scopes with
    `# kinds=`. The curated scope is `class,const,function,method,test`. The
    source manifest includes `main.go::type::scopeMode` from Chiasmus `v0.3.4`.
  - The repo lives on an exFAT volume that grows AppleDouble `._*` sidecars;
    `._foo_spec.cr` breaks spec discovery. `make format|lint|test` and
    `make clean` strip them first.
  - The CLI harness always passes `ROD_CHROME_BIN` so the suite stays offline
    instead of downloading a ~130 MB snapshot. Timeouts that need to expire in a
    spec are shortened with `ROD_TIMEOUT` (e.g. `"0.5"`), the same variable
    rodney reads; pass it through `CLISpecHarness#run(..., env: ...)`.
  - `_proxy` is a raw `TCPServer`, not an `HTTP::Server`, because Go hijacks
    CONNECT (`main.go:1930-1943`) and Crystal's server cannot hand a connection
    back. Do not "simplify" it into `HTTP::Server`; that is what produced the
    old 501.
  - `shard.yml` tracks rod `branch: main` (locked at `46e6c7f`) because the
    fixes this repo needs are not tagged yet. Go back to tag tracking when a
    release contains them.
  - `webb axtree`/`axfind`/`axnode` still work as unadvertised aliases (Go
    rejects them as unknown commands); the usage text uses Go's hyphenated
    names.
  - Suite runtime tracks host load (`uptime`): ~40 s idle, minutes at load > 20.
    Chrome launch retries three times because it intermittently loses the
    debug-URL race under load.
- **Last port commit:** `port: give forward Go's conditional URL output`
  (`72983cf`).
- **Gates (2026-11-19):** `make format`, `make lint` (5 files), `make test`
  (158 examples), `make build` (CLI), `make inventory` (82 curated / 83 source /
  63 tests on `chiasmus-tree-sitter` v0.3.4) passed; `make parity-verify`
  passed earlier in the day.

## How features are sliced

Each checklist item below is **one feature = one commit**, sized so it:

1. changes one behavior area only — one CLI flag, one command, one harness
   piece, one ledger migration;
2. lands its spec in the same commit (red → green), never after;
3. updates the ledger rows for that behavior only, then runs `make inventory`;
4. stays reviewable in one sitting and revertible on its own.

If an item needs a second area, split it into two items instead of widening it.
Do not batch items: a commit that closes two checkboxes is two features.

## Next feature: `cmdClearCache`

Go (`vendor/rodney/main.go:608-616`) sends
`proto.NetworkClearBrowserCache{}.Call(page)`, checks the error with
`fatal("clear cache failed: %v", err)`, then prints `Browser cache cleared`.

Crystal's `cmd_clear_cache` calls
`Cdp::Network::ClearBrowserCache.new.call(page)` bare, so a failed request
escapes as an unhandled exception (exit 1 + stack trace) where Go prints
`error: clear cache failed: <cause>` and exits 2.

Green shape: the same `begin`/`rescue`/`Webb.fatal("clear cache failed: ...")`
block `cmd_reload`'s `--hard` branch just got.

Red proof: a failing `Network.clearBrowserCache` is not CLI-reachable, so write
the characterization first (`clear-cache` prints `Browser cache cleared` and
exits 0, and navigation still works afterwards), then apply the rescue and
re-run. Upstream has no test for this command either.

## Open ledger hygiene

- [ ] **Audit `cmdOpen`'s ignored upstream errors** — Go discards both the
      `browser.Pages()` and `page.Info()` errors in `cmdOpen`
      (`pages, _ :=`, `info, _ :=`, `vendor/rodney/main.go:549-568`), so a
      listing failure falls through to "create a page" and an info failure
      prints nothing; Crystal fatals `failed to list pages: <cause>` and raises
      on the info failure. Either match upstream or record the divergence and
      adjust the row's note.
- [ ] **Re-base the ledger on a pin change** — only when `vendor/rodney` moves
      off `v0.4.0`: rewrite the `# baseline=` header and rows for the new tag in
      one commit; never append across releases.

## History

Completed work, split by area. Read only what you are changing:

- [`history-cli.md`](history-cli.md) — every completed command entry (the
  `--insecure` test, the harnesses, `stop`/`start`/`status`/`connect`,
  `select`/`submit`, screenshot/sleep diagnostics, the empty-browser semantics,
  the CONNECT proxy, `attr`, the element checks, `assert`, and the AX commands).
- [`history-ledger.md`](history-ledger.md) — how the ledger and the tree-sitter
  gates got their current shape.
- [`history-shard.md`](history-shard.md) — why each `dsisnero/rod` pin mattered
  (`wait_stable`, `strip_first_dir`, `IdleCounter`, the event hub, manager
  logging).

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

- `webb start --show` works. Upstream's `help.txt` advertises it, but
  `cmdStart`'s validation loop accepts only `--insecure`/`-k`, so
  `rodney start --show` exits 2 with `unknown flag: --show`. Crystal accepts the
  flag (and keeps `[--show]` in its own unknown-flag usage line). Pinned by
  `spec/cli_spec.cr` → "accepts --show, which upstream advertises but rejects".
- `webb axtree`/`axfind`/`axnode` are accepted as aliases; Go only knows the
  hyphenated command names. Unadvertised, and the usage text uses Go's names.
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case. No open
  shard gaps and `shard_issues/` is empty: `Page#wait_stable` now runs
  `WaitRequestIdle` (rod `c459108`), the managed download strips its archive
  root on exFAT (rod `5e6a630`, an intentional exFAT-only shim recorded in the
  shard's own `plans/parity.md`), and `IdleCounter#wait` returns cleanly when
  its context is cancelled (rod `7356dd8`).
