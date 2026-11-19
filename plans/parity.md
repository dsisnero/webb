# Parity Plan — webb

<!--
Curated feature roadmap for the Crystal port of simonw/rodney. Per-symbol state
lives in `plans/inventory/`; keep this file human-curated. Every checklist item
is one feature: one branch, one commit, one ledger update.
-->

## Where we are

- **Current focus:** slicing the remaining 45 `partial` ledger rows into
  features. The command-level port is complete: `cmdStart`, `cmdWaitStable`, the
  `_proxy` helper (CONNECT tunneling), and `cmdStatus` were the rows with
  concrete divergence notes, and the `lib/rod` gaps behind them are fixed
  upstream.
- **Next up:**
  1. Slice the remaining `partial` rows into features. List them with
     `awk -F'\t' '$3=="partial"' plans/inventory/go_port_inventory.tsv`; most
     only need output/error coverage, which the CLI harness makes cheap. Start
     with rows whose note names a specific divergence — `cmdTitle` is next
     (`page.info` has no Go `failed to get page info` fatal), then the AX
     commands (`cmdAXTree`/`cmdAXFind`/`cmdAXNode`).
  2. Re-base the ledger when the pin moves off `v0.4.0`.
  3. Split this file once it passes one screen (Phase 2).
  4. Optional: add a Chrome-through-the-proxy example. The `_proxy` contract is
     covered at the socket level, not yet with a real HTTPS origin.
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 64 examples. `spec/cli_spec.cr`: 46 examples (19
    process-contract, 3 `_proxy`, 4 `start` session, 20 live-browser). Suite
    total: 110 examples, 0 pending, 0 failures.
  - Curated ledger: 145 rows across 82 source declarations and 63 upstream
    tests. All 78 function IDs have Crystal references: 31 are `ported`, 45
    `partial`, and 2 `intentional_divergence`. The pin has no receiver method
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
  - The CLI harness always passes `ROD_CHROME_BIN` so the suite stays offline;
    rod's launcher would otherwise download a ~130 MB snapshot. The managed path
    now works on this volume too (rod `5e6a630` ignores `._*` when stripping the
    archive's top-level folder).
  - `shard.yml` tracks rod `branch: main` (locked at `46e6c7f`) because the
    fixes this repo needs are not tagged yet. Go back to tag tracking when a
    release contains them.
  - `_proxy` is a raw `TCPServer`, not an `HTTP::Server`, because Go hijacks
    CONNECT (`main.go:1930-1943`) and Crystal's server cannot hand a connection
    back. Do not "simplify" it into `HTTP::Server` again; that is what produced
    the old 501.
  - Suite runtime tracks host load (`uptime`): ~30 s idle, minutes at load
    > 20. Chrome launch retries three times because it intermittently loses
    the debug-URL race under load. If a run looks slow, check the load and
    `crystal spec spec/cli_spec.cr --profile` before suspecting the harness.
- **Last port commit:** `port: give status Go's four output paths` (see
  `git log -1 --oneline`).
- **Gates (2026-11-19):** `make format`, `make lint` (5 files), `make test`
  (110 examples), `make build` (CLI), and `make parity-verify` passed.
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
      - Follow-up (closed below): `lib/rod`'s `wait_stable` waited a fixed
        duration where go-rod races `WaitRequestIdle`, so the row stayed
        `partial` until that shard gap closed.
- [x] **Close the `lib/rod` gaps behind `waitstable` and `start`** — both were
      fixed in `dsisnero/rod` on `main` and adopted here by moving the pin.
      - `c459108` *wait_stable waits on the request queue like go-rod*:
        `wait_stable`'s middle fiber calls `wait_request_idle(d).call`
        (`page.go:821` races `WaitLoad`, `WaitRequestIdle(d,nil,nil,nil)()`,
        `WaitDOMStable(d,0)`); the port had substituted `wait_duration(d)` while
        `wait_request_idle` sat unused.
      - `5e6a630` *strip the managed download's top-level dir on exFAT*: this
        volume makes `unzip` write `._chrome-mac` next to the archive root, so
        the strict single-entry guard skipped the strip and `bin_path` dangled
        after a successful download. `strip_first_dir` now ignores `._*` and
        `.DS_Store` when counting and moving entries. Documented upstream as an
        exFAT-only shim (inert on APFS/HFS+/Linux).
      - Red → green here: with the pin on `1f7636a`, `webb waitstable` against a
        page polling a 2 s route returned in **1.23 s**; with `c459108` it waits
        **≥ 3.5 s** (new `cli_spec.cr` example). Running `start` with no
        `ROD_CHROME_BIN` reproduced the download failure end to end
        (`chromium-<rev>/Chromium.app/...: No such file or directory`, 359 MB
        left in the temp home) before `5e6a630`.
      - Spec detail worth keeping: go-rod only sees requests that **start after**
        the wait subscribes, and it still ends once `d` idle elapses. The fixture
        therefore polls (`setInterval`) instead of firing one late request.
      - Correction recorded so it is not re-investigated: rod.003 §1 was wrong —
        go-rod's `NewBrowser` sets `Logger: log.New(os.Stdout, ...)`
        (`browser.go:107`) and hands it to `fetchup` (`browser.go:140`), so
        download progress on stdout is upstream behavior and the port keeps it.
      - Ledger: `cmdWaitStable` → `ported`. `shard_issues/rod.002.md` and
        `rod.003.md` are deleted (closed).
- [x] **Port the authenticated proxy (CONNECT tunneling)** — `_proxy` answered
      `501 Not Implemented` for CONNECT because Crystal's `HTTP::Server` cannot
      hijack a socket. That was our own handler's shape, not a port limit: the
      rodney contract is `vendor/rodney/main.go:1870-1980`, and a proxy does not
      need `HTTP::Server` at all.
      - Green: `cmd_internal_proxy` now serves raw `TCPSocket`s on
        `127.0.0.1:<port>` and parses each request with `HTTP::Request.from_io`
        before dispatching, the way `net/http` does. `proxy_connect` dials the
        operator's proxy with Go's 30 s timeout, sends
        `CONNECT <authority>` with `Proxy-Authorization`, inspects bytes 9..12 of
        the reply (a split reply is rejected exactly as in Go), answers
        `HTTP/1.1 200 Connection Established`, then splices both ways.
        `proxy_http` forwards the absolute-form request upstream and copies the
        response back with hop-by-hop framing rewritten.
      - Error paths keep Go's `http.Error` shape: `502` plus
        `upstream dial failed` / `upstream write failed` / `upstream read failed`
        / `upstream rejected CONNECT` / `upstream request failed` as
        `text/plain` with `nosniff`, and a listen failure fatals with
        `proxy listen failed: ...`.
      - Coverage: `CLI auth proxy` runs the real helper process against a
        `CONNECT`-capable upstream fixture — a tunnel round trip through an echo
        server, an upstream `407` surfacing as Go's `502
        upstream rejected CONNECT`, and a plain HTTP request forwarded with
        credentials. Upstream rodney has no proxy tests at all, so this is
        coverage the Go tree does not have.
      - Socket ownership: the client socket is closed once by the connection
        handler, never by the copy fiber. Closing it in both places crashed the
        spec process (a double close on a recycled descriptor), which is why the
        splice helper leaves the client to its owner.
      - Found in `lib/rod` while proving it: `IdleCounter#wait`
        (`src/rod/util/utils.cr`) used `ctx.done.receive` in its `select`, and a
        cancelled context *closes* that channel, so the fiber `wait_request_idle`
        spawns died with `Channel::ClosedError` and printed
        `Unhandled exception in spawn` on the CLI's stderr (any `waitstable` or
        `waitidle` run could hit it). Fix prepared with a red → green spec in
        the shard: `ctx.done.receive?` in that branch plus a spec
        (`spec/utils_sleeper_spec.cr`), landed as rod `7356dd8`.
      - Ledger: `cmdInternalProxy`, `proxyConnect`, and `proxyHTTP` → `ported`.
        `shard_issues/rod.001.md` is deleted (closed).
      - Same bug class, adopted right after: rod `f3439cb` makes `Pipe#write`,
        `Pipe#run_loop`, and `Observable#subscribe`'s cleanup use
        `done.receive?`, so a publish that races a shutdown no longer raises out
        of `Observable#publish` and stops `Browser#init_events` for the rest of
        the session. No webb change was needed.
      - Also adopted, no webb change needed: rod `46e6c7f` gives `Manager#logger`
        go-rod's `utils.Logger` shape (defaulting to quiet) and emits the four
        manager events Go logs. webb never uses `Manager`; `webb start` still
        prints exactly Go's two lines and nothing on stderr (re-checked by hand
        after the bump).
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
        default, so `cmd_start` needs no logger workaround. Download progress
        still prints on stdout, which is correct: go-rod's `NewBrowser` installs
        a stdout logger (`browser.go:107`) and hands it to `fetchup`
        (`browser.go:140`), so quieting it would be the divergence.
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
- [x] **Give `status` Go's four output paths** — the row carried the note that
      only the zero-page case was covered. `cmd_status` also disagreed with Go on
      the error branches: it called the fatal `Webb.load_state`, so a missing or
      corrupt state file exited 2 with `error: no browser session ...` where Go
      prints `No active browser session` and exits 0 (`main.go:505-510`).
      - Red: `status` with an empty `RODNEY_HOME` printed the fatal on stderr and
        exited 2; a `{not json` state file printed
        `error: corrupt state file: ...` and exited 2.
      - Green: `load_state?` (Go's error return) supplies the session, both error
        cases print the stdout line and exit 0, and a page-listing failure now
        degrades to `Pages: 0` like Go's ignored `pages, _ := browser.Pages()`.
      - Coverage: four examples — no session, corrupt state, unreachable session
        (`Browser not responding (PID 4242, state may be stale)`), and a live
        session asserting the exact five lines, read back from the state file so
        `connect`'s `chrome_pid: 0` rewrite cannot mask a mismatch.
      - Ledger: `cmdStatus` → `ported`; `loadState` note now records that both
        `cmd_start` and `cmd_status` use `load_state?`.
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
- `lib/rod/` carries local patches against `dsisnero/rod`; each deliberate
  divergence is documented in `shard_issues/` with a reproducible case. No
  open shard gaps and `shard_issues/` is empty: `Page#wait_stable` now runs
  `WaitRequestIdle` (rod `c459108`), the managed download strips its archive
  root on exFAT (rod `5e6a630`, an intentional exFAT-only shim recorded in the
  shard's own `plans/parity.md`), and `IdleCounter#wait` returns cleanly when
  its context is cancelled (rod `7356dd8`).
