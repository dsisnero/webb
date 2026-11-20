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

- **Current focus:** `cmdDownload` (details in the **Files** block below), then
  the rest of the **Queue** block — 17 `partial` ledger rows split into 6 CLI
  commands and 11 helpers, each with its Go contract and reachability recorded
  so a fresh session can start without re-deriving state.
- **Next up (in order):**
  1. **`cmdDownload`** — `element not found:` on the lookup, `download failed:`
     around the page-context fetch, `failed to write file:` around the write.
  2. **`cmdFile`** — lookup and `set file` fatals, plus a real message
     divergence on its stat branch (`stat <path>: no such file or directory`).
  3. Waits: **`cmdWait`** (lookup red), then spec-only **`cmdWaitLoad`** and
     **`cmdWaitIdle`**.
  4. **`cmdScreenshotEl`**.
  5. The 11 helper rows — unit specs, no product code.
  6. Hygiene: SIGPIPE proof for `init`, `cmdOpen`'s ignored errors, ledger
     re-base on the next `vendor/rodney` pin.
- **Optional:** a Chrome-through-the-proxy example against a real HTTPS
  origin; today `_proxy` is proven at the socket level.
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 72 examples. `spec/cli_spec.cr`: 113 examples (22
    process-contract, 3 `_proxy`, 4 `start` session, 84 live-browser). Suite
    total: 185 examples, 0 pending, 0 failures.
  - Curated ledger: 145 rows across 82 source declarations and 63 upstream
    tests. All 78 function IDs have Crystal references: **59 `ported`, 17
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
  - `shard.yml` tracks rod `branch: main` (locked at `35d540d`) because the
    fixes this repo needs are not tagged yet. Go back to tag tracking when a
    release contains them.
  - `webb axtree`/`axfind`/`axnode` still work as unadvertised aliases (Go
    rejects them as unknown commands); the usage text uses Go's hyphenated
    names.
  - Suite runtime tracks host load (`uptime`): ~40 s idle, minutes at load > 20.
    Chrome launch retries three times because it intermittently loses the
    debug-URL race under load.
- **Last port commit:** `port: give pdf Go's generate/write fatals`
  (`6f56a0c`).
- **Gates (2026-11-20):** `make format`, `make lint` (5 files), `make test`
  (185 examples), `make build` (CLI), `make inventory` (82 curated /
  83 source / 63 tests on `chiasmus-tree-sitter` v0.3.4) passed;
  `make parity-verify`
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

## Queue: files, waits, screenshot element, helpers

Ordered so one commit closes one row. Each item records the Go contract and
whether its red is reachable from the CLI; "spec only" items already match Go
and just need the characterization that lets the row go `ported`.

Resume with `make lint` + `make test` first (185 examples, 0 pending), then:

```bash
crystal spec spec/cli_spec.cr:<line>   # one example while iterating
make test && make inventory            # full gates before the commit
```

Known flakes, not regressions: `waitstable`'s timing example
(`waits about a second for DOM stability`) and the `download`/`file` browser
parity examples fail under host load and pass on a re-run or in isolation.
Check `uptime` before believing a red.

### Files

- **`cmdDownload`** (`main.go:836-899`) — five fatals, three reachable:
  `element not found: %v` (bare `page.element` today), `download failed: %v`
  around the page-context fetch, and `failed to write file: %v` around the
  write. `failed to decode data URL:` and `failed to decode response:` need a
  malformed fixture and stay structural. The suite already has `Webb.download`
  browser parity, so the CLI example should cover `-` (raw bytes to stdout) and
  the inferred filename instead of repeating the fetch path.
- **`cmdFile`** (`main.go:792-834`) — `element not found: %v`,
  `failed to read stdin:` / `failed to create temp file:` / `failed to write
  temp file:` on the `-` branch, `failed to set file: %v`, and a **message
  divergence** on the stat branch: Go prints
  `error: file not found: stat <path>: no such file or directory`, Crystal
  prints `error: file not found: <path>`. That stat text is the reachable red,
  and fixing it means carrying the OS error, not just the path. The same
  wording gap exists in every wrapped `os.WriteFile` fatal (`pdf`, `download`,
  `screenshot*`): Crystal prints its own `File::NotFoundError` text after the
  Go prefix. Normalize it in one helper when the stat branch lands, then re-run
  the write-path examples.

### Waits

- **`cmdWait`** (`main.go:1047-1057`) — `element not found: %v` then
  `MustWaitVisible()`. Lookup red is reachable; proving the *wait* needs a
  fixture element that appears late (extend the fixture server, do not sleep in
  the spec).
- **`cmdWaitLoad`** (`main.go:1059-1063`) and **`cmdWaitIdle`**
  (`main.go:1069-1073`) — spec only: upstream checks no errors here, so a
  characterization printing `Page loaded` / `Network idle` at exit 0 is the
  whole contract.

### Screenshot element

- **`cmdScreenshotEl`** (`main.go:1172-1192`) — `element not found: %v`,
  `screenshot failed: %v`, `failed to write screenshot: %v`. The lookup and the
  write are both reachable (`screenshot-el` into a missing directory); the
  capture branch is structural.

### Helpers with no CLI surface

These 11 rows are `partial` because nothing pins them, not because they are
wrong. Unit specs close them without touching product code:

- `formatAXNodeList`, `formatAXNodeDetail` — covered indirectly by the AX
  command specs; want direct edge cases (empty list, missing name/role, the
  JSON variant).
- `formatProperties` — no coverage at all; Go prints `name: value` lines from
  `axnode`'s properties.
- `detectProxy` — environment priority (`HTTPS_PROXY` before `HTTP_PROXY`),
  malformed URLs, and the no-proxy case; `spec/cli_spec.cr` already has the
  proxy server helpers.
- `nextAvailableFile` — `base`, `base-2`, `base-3` in a temp dir
  (`Webb.next_available_file`).
- `connectBrowser` — `start`/`status`/`connect` specs cover the success and
  connect-error paths; needs a direct stale-`debug_url` example.
- `loadState`, `saveState`, `removeState` — `start`/`stop` cover them
  indirectly; `load_state` wants the nil-on-garbage contract, `save_state` the
  write-failure fatal, `remove_state` the ignores-removal-errors branch.
- `init` — `Webb::DEFAULT_TIMEOUT` is the load-time equivalent of Go's
  `init()`; the row wants one example per env case (unset, valid, garbage) plus
  the SIGPIPE verification below.
- `proc_unix.go::setSysProcAttr` — Crystal parity is structural (no `Setsid`);
  needs a note-level justification plus the existing process specs that prove
  the helper survives `stop`.

## Open ledger hygiene

- [ ] **Verify SIGPIPE handling for `init`** — Go's second `init()`
  (`main.go:455-457`) ignores `SIGPIPE`, so `webb js` piped into `head` exits 0
  instead of dying on a closed stdout. Pin it with a spec (`webb js ... | head
  -1` style) before flipping the row.
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
  shard gaps and `shard_issues/` is empty: the latest, `select_all_text`
  selecting a document Range instead of Go's `this.select()` (which made
  `input` append and `clear` a no-op), landed as rod `35d540d` and was retired
  with the rest — `Page#wait_stable` runs `WaitRequestIdle` (rod `c459108`),
  the managed download strips its archive root on exFAT (rod `5e6a630`, an
  intentional exFAT-only shim recorded in the shard's own `plans/parity.md`),
  and `IdleCounter#wait` returns cleanly when its context is cancelled
  (rod `7356dd8`).
