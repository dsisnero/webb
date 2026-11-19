# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated. Every checklist item
is one feature: one branch, one commit, one ledger update.
-->

## Where we are

- **Current focus:** the `lib/rod` gap behind `cmdWaitStable`. `Page#wait_stable`
  waits a fixed duration where go-rod also runs `WaitRequestIdle`
  (`shard_issues/rod.002.md`). `cmdStart` is done and is now the last function
  row that needed work.
- **Next up:**
  1. Fix `rod`'s `Page#wait_stable` to call `wait_request_idle` like go-rod
     (`shard_issues/rod.002.md`), then re-check the `cmdWaitStable` timing spec
     and sign that row off.
  2. Slice the remaining `partial` rows into features. List them with
     `awk -F'\t' '$3=="partial"' plans/inventory/go_port_inventory.tsv`; most
     only need output/error coverage, which the CLI harness makes cheap. Start
     with rows whose note names a specific divergence.
  3. Re-base the ledger when the pin moves off `v0.4.0`.
  4. Split this file once it passes one screen (Phase 2).
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 64 examples. `spec/cli_spec.cr`: 38 examples (17
    process-contract, 4 `start` session, 17 live-browser). Suite total: 102
    examples, 0 pending, 0 failures.
  - Curated ledger: 145 rows across 82 source declarations and 63 upstream
    tests. All 78 function IDs have Crystal references: 26 are `ported`, 49
    `partial`, and 3 `intentional_divergence`. The pin has no receiver method
    IDs. All 63 upstream test rows are `ported`; no test row is `partial`.
  - Source manifest: 83 declarations at `v0.4.0` (1 class, 3 constants, 78
    functions, and 1 type). Implementation statuses are in the curated
    ledger. The generated source snapshot keeps its discovery baseline
    statuses; `scopeMode` still needs a curated type mapping.
  - CLI harness: `spec/cli_spec.cr` builds `src/main.cr` into
    `temp/cli_spec/webb` once. `run_cli` uses an empty `RODNEY_HOME`;
    `run_cli_live` points at `browser_home/state.json`; `state_home`,
    `session_home`, and `owned_browser` set up `stop` and `start` scenarios.
    Chrome runs with `--no-startup-window`, so a fresh browser has **zero
    pages**.
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
  - The CLI harness always passes `ROD_CHROME_BIN`. Without it, rod's launcher
    downloads a managed build that cannot be found on this exFAT volume, because
    macOS's `._*` sidecars defeat the downloader's `strip_first_dir` step
    (`shard_issues/rod.003.md`).
  - `shard.yml` tracks rod `branch: main` (locked at `1f7636a`) because the
    launcher output-contract fix is not tagged yet. Go back to tag tracking when
    a release contains it.
  - Retained intentional divergence: HTTPS `CONNECT` proxying returns 501
    because Crystal's `HTTP::Server` cannot hijack the socket
    (`shard_issues/rod.001.md`, `src/cli.cr` proxy handler).
  - Suite runtime tracks host load (`uptime`): ~30 s idle, minutes at load
    > 20. Chrome launch retries three times because it intermittently loses
    the debug-URL race under load. If a run looks slow, check the load and
    `crystal spec spec/cli_spec.cr --profile` before suspecting the harness.
- **Last port commit:** `port: make start match Go's lifecycle behavior` (see
  `git log -1 --oneline`).
- **Gates (2026-11-19):** `make format`, `make lint` (5 files), `make test`
  (102 examples), `make build` (CLI), and `make parity-verify` passed.
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
      The usage is now `vendor/rodney/help.txt` byte-for-byte with only the CLI
      name changed, and a spec compares the full text so future command changes
      cannot drift silently. Ledger: `main` and `printUsage` → `ported`.
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
- [x] **Align `cmd_wait_stable` with Go's `MustWaitStable()`** — `src/cli.cr`
      passed `100.milliseconds` where Go waits `time.Second`.
      - Red: a live spec timed `webb waitstable` at 166 ms against a 900 ms
        floor derived from `MustWaitStable()` = `WaitStable(time.Second)`.
      - Green: the call is now `wait_stable(1.second)`; the spec asserts
        `DOM stable`, exit 0, empty stderr, and an elapsed time of at least
        900 ms (10% slack for process startup).
      - The row stays `partial`: `lib/rod`'s `wait_stable` still waits a fixed
        duration where go-rod waits for `WaitRequestIdle`, so a page with
        in-flight requests finishes early. Recorded as
        `shard_issues/rod.002.md` with a reproduction and the one-line fix.
- [x] **Match Go's page semantics on an empty browser** — Crystal used to
      fabricate `about:blank` where Go fails; the divergence reached every
      command through `withPage` and `open`.
      - Red: `webb title` with zero pages exited 0 in the harness (a fresh
        launcher passes `--no-startup-window`, so zero pages is the default
        start state); Go prints `no pages open` and exits 2.
      - Green: `getActivePage` now matches Go exactly (empty → fatal, listing
        failure → `failed to list pages: ...`, index clamped to 0), `withPage`
        fatals with rod's own message instead of a Crystal wrapper, and `open`
        follows Go's own load/connect/list branch: create a page at the URL
        when none are open (saving `active_page` 0), else navigate.
      - Follow-on bug caught by the harness: `status` began exiting 2 on zero
        pages because `fatal` cannot be rescued. Go prints `Pages: 0` and skips
        the `Current:` line, so `status` now guards on `pages.empty?`; the spec
        asserts exit 0 and no `Current:`.
      - Ledger: `getActivePage`, `withPage`, and `cmdOpen` → `ported`;
        `cmdStatus` note updated (still `partial`).
      - Harness: `reset_pages` closes every page through one long-lived control
        connection (never `Browser#close`, which shuts Chrome down), so a spec
        can start from zero pages deterministically.
- [x] **Match Go's `connect` validation and error paths** — the row carried a
      concrete note: the Crystal regex rejected the bracketed IPv6 `host:port`
      that Go accepts, and every failure path lost Go's diagnostic.
      - Red: `connect [::1]:1` failed validation (Go reaches the fetch), and
        `connect 127.0.0.1:1` exited 1 with an unhandled `Socket::ConnectError`
        instead of Go's `error: could not reach browser at ...: <cause>`.
      - Green: `valid_host_port?` mirrors `net.SplitHostPort` (bracketed IPv6,
        numeric port, extra colons rejected, explicit trailing colon allowed);
        the fetch, JSON parse, connect, and save steps each fatal with Go's
        message, including the underlying cause.
      - Crystal has no stdlib `SplitHostPort`; the helper is Go's own algorithm
        ported to `String` primitives rather than a new convention.
      - Coverage: four process-level examples plus a live `connect` that stores
        the debug URL and then prints the fixture title. Ledger: `cmdConnect` →
        `ported`.
- [x] **Quote JS literals in `select` and `submit`** — both interpolated raw
      arguments into a JS string, so a selector like `form[id="search-form"]`
      or a value containing a quote produced invalid JS. The ledger note was
      also wrong: Go does not pass arguments, it interpolates `%q`-quoted
      literals.
      - Red: four live examples failed — quoted value, quoted selector, missing
        selector (`select`), and missing form (`submit`, which also exited 1
        instead of 2).
      - Green: both commands interpolate `to_json` (the Crystal equivalent of
        Go's `%q`), `select` fatals with `select failed: ...` on eval errors,
        `submit` fatals with `form not found: ...` on a missing element, and
        `Selected:` now prints the returned string rather than its JSON form
        (`JSON::Any#to_s` keeps the quotes; it uses `as_s`).
      - No new convention: an eval failure after the element check stays an
        unhandled exception, exactly how this port treats every Go `Must*` call.
      - Fixture gained a `<select id="topic">` with a quoted option value and a
        `<form id="search-form">`. Ledger: `cmdSelect` and `cmdSubmit` →
        `ported`.
- [x] **Match Go's numeric argument diagnostics (`screenshot`, `sleep`)** —
      both rows carried concrete notes about Crystal conversion errors escaping
      as raw exceptions.
      - Red: `sleep abc` exited 1 instead of `error: invalid seconds: ...`;
        `screenshot -w` printed a hardcoded `--width` where Go echoes the flag
        actually used; `screenshot -w abc` / `-h xyz` exited 1 instead of
        `error: invalid width/height: ...`.
      - Green: `sleep` fatals with `invalid seconds: ...`, and `screenshot`
        echoes the real flag in `missing value for <flag>` and fatals with
        `invalid width/height: ...`. Dimensions parse as 64-bit ints, matching
        Go's `int` on this platform.
      - Same row, same class: `screenshot` also gained Go's `failed to set
        viewport`, `screenshot failed`, and `failed to write screenshot`
        diagnostics instead of unhandled exceptions.
      - Verified Crystal's `String#to_i`/`to_f` are already strict, so the only
        gap was diagnostics and exit codes; a negative sleep exits 0 in both.
      - Ledger: `cmdScreenshot` and `cmdSleep` → `ported`.
- [x] **Make `stop` match Go's lifecycle behavior** — Crystal printed
      `Browser disconnected` for external sessions and `Browser not responding`
      for stale ones, plus TERM/connect chatter Go never emits. Go always ends
      with `Chrome stopped`.
      - Red: an external session and a stale session both printed the wrong
        line; the no-session message already matched because `load_state` fatals
        before the old rescue could run.
      - Green: `cmd_stop` follows Go — `load_state` fatal, connect and close the
        browser only when `chrome_pid > 0`, TERM by PID when the connection
        fails, TERM the proxy helper, remove state, print `Chrome stopped`.
      - Coverage: a process example for the no-session path, plus live examples
        for an external session (browser must survive), a stale session, and an
        owned throwaway Chrome (the process must die). The harness gained
        `state_home` and `owned_browser`, and reuses one `new_launcher` helper.
      - Ledger: `cmdStop` → `ported`. `cmdStart` became the only row left with a
        concrete divergence note, and it is the next entry.
- [x] **Make `start` match Go's lifecycle behavior** — compared
      `vendor/rodney/main.go:321-428` with `src/cli.cr::cmd_start`.
      - **Launcher flags:** added `single-process` ("required for screenshots in
        gVisor/container environments"); the live screenshot example still
        passes.
      - **Already-running check:** Go closes the saved browser and removes the
        state only when it actually connected; a stale or corrupt state file is
        left in place and nothing is printed. `cmd_start` now calls
        `close_running_session`, which uses the new `Webb.load_state?` (Go's
        error return) instead of the fatal `load_state`. The old
        `Warning: stale state file removed` line is gone.
      - **Save failure:** `save_state` raises now become Go's
        `failed to save state: ...` fatal (exit 2, not 1).
      - **Extra output:** dropped Crystal's third line, `Data directory: ...`.
      - **Log noise:** rod's launcher used to log `Launching browser: ...` at INFO
        on stdout, which go-rod never prints (its logger is `io.Discard`).
        Fixed upstream in `dsisnero/rod` `1f7636a`, which removes the `::Log`
        property and makes `logger(io : IO)` the only sink API with a discard
        default, so `cmd_start` needs no logger workaround. The downloader still
        logs at INFO on the managed path (`shard_issues/rod.003.md`).
      - **Proxy helper:** still spawned with `Process.new` (no `setsid`), but its
        stdio now goes to `/dev/null` the way Go's nil stdio does. That is what
        lets the helper outlive the parent without holding the caller's pipes
        open; a spec proves the helper is alive after `start` exits and gone
        after `stop`. Without the redirect, `Process.run` in the harness would
        wait on the inherited pipe forever.
      - **`--show` (decision):** upstream advertises `start --show` in
        `help.txt` but `cmdStart`'s validation loop rejects it (`unknown flag:
        --show`, exit 2), so the feature is unreachable in Go. Decision: keep
        Crystal's working `--show` and record an intentional divergence. The
        spec pins it without opening a window: `start --show --bogus` reports
        `unknown flag: --bogus`, proving `--show` passed validation, and the
        usage keeps advertising it. Consequently the unknown-flag usage line
        stays `usage: webb start [--insecure] [--show]` rather than Go's
        `[--insecure]`; that is part of the same divergence.
      - **Coverage:** four new examples — start writes state and `stop` kills the
        browser (asserts the exact two-line stdout), a second `start` closes the
        live session and replaces it, a stale state file is preserved when the
        launch fails, and the proxy branch records `proxy_pid`/`proxy_port` and
        the helper dies with `stop`. The harness gained `session_home`,
        `read_state`, `wait_until_gone`, `discard_session`, and an `env`
        parameter on `run`.
      - **Ledger:** `cmdStart` → `intentional_divergence` (every Go behavior
        matches; the only difference is the documented `--show` superset, which
        the plan's `partial`/`ported` choice does not describe). `loadState`,
        `saveState`, `connectBrowser`, and `proc_unix.go::setSysProcAttr` notes
        updated to say what is now covered and what still is not.
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

- `webb start --show` works. Upstream's `help.txt` advertises it, but
  `cmdStart`'s validation loop accepts only `--insecure`/`-k`, so
  `rodney start --show` exits 2 with `unknown flag: --show`. Crystal accepts the
  flag (and keeps `[--show]` in its own unknown-flag usage line). Pinned by
  `spec/cli_spec.cr` → "accepts --show, which upstream advertises but rejects".
- HTTPS `CONNECT` proxy: Crystal's `HTTP::Server` cannot hijack the socket, so
  proxy tunneling answers `501 Not Implemented` instead of tunneling
  (`shard_issues/rod.001.md`).
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case. Open
  shard gaps: `Page#wait_stable` skips go-rod's `WaitRequestIdle`
  (`shard_issues/rod.002.md`), and the managed-browser download path logs at
  INFO and cannot strip the archive root on this exFAT volume
  (`shard_issues/rod.003.md`; its launcher-log half is fixed upstream in
  `1f7636a`).
