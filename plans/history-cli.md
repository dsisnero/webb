# History — CLI commands and the spec harness

> Completed work, kept for the reasoning behind each port. A new session does
> not need this file unless it is changing behavior described here; the ledger
> (`plans/inventory/go_port_inventory.tsv`) is the current-state artifact and
> `plans/parity.md` has the next work.

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

## Command-by-command parity (completed)

Each entry below was one commit: the API surface, the upstream (or equivalent)
spec, the ledger update, and this write-up.

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
      - Ledger: `cmdInternalProxy`, `proxyConnect`, and `proxyHTTP` → `ported`.
        `shard_issues/rod.001.md` is deleted (closed).
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
- [x] **Give `attr` Go's element and attribute errors** — `cmd_attr` called
      `page.element` unguarded, so a selector that matches nothing escaped as an
      unhandled `Rod::ElementNotFoundError` (exit 1) where Go wraps any
      `Element()` error as `fatal("element not found: %v", err)` (exit 2,
      `main.go:712-717`).
      - Red: `attr #missing id` exited 1 with a stack trace.
      - Green: the lookup is wrapped and fatals with Go's prefix. The wrapped
        cause is go-rod's *page deadline* (`context deadline exceeded`), not the
        not-found text — Go's retry loop returns the context error once
        `page.Timeout` expires, so the spec pins that message.
      - Coverage: four examples — value output (`aria-label` → `Topic`), missing
        element (with `ROD_TIMEOUT=0.5`, the same variable rodney reads, so the
        lookup is fast), missing attribute (`attribute "data-nope" not found`),
        and the usage fatal.
      - Ledger: `cmdAttr` → `ported`.
- [x] **Give the element checks Go's error contract** — `cmd_exists` and
      `cmd_count` let a broken selector escape as an unhandled CDP error (exit
      1) instead of Go's `query failed: %v` fatal (exit 2), and `cmd_visible`
      returned the raw exception instead of Go's `false` + exit 1.
      - Red: `exists <<<` / `count <<<` exited 1; `visible <<<` exited 1 with
        `Unhandled exception: {-32000 DOM Error while querying }` on stderr.
      - Green: both queries wrap the lookup and fatal with Go's prefix;
        `visible` now uses `page.element` like Go's `Element` (so a missing
        selector waits for the page timeout, as upstream does) and turns every
        lookup or visibility error into `false` + exit 1.
      - Coverage: existence (`true`/0, `false`/1), counts (3 matches, 0 for a
        missing selector), visibility (visible, `#hidden`, and a missing
        selector under `ROD_TIMEOUT=0.5`), both `query failed` fatals, `visible`
        with a broken selector, and the three usage fatals. The fixture gained a
        `#hidden` element (`display:none`).
      - Ledger: `cmdExists`, `cmdCount`, and `cmdVisible` → `ported`.
- [x] **Audit and cover `assert`** — the row asked for CLI exit status and
      output together, and the source carried a `browser.close` in
      `Webb.cmd_assert`'s `ensure` that Go's `cmdAssert` does not have
      (`withPage` documents "Caller should NOT close the browser").
      - Expected red, got green: the close never ran, because Crystal's `exit`
        does not unwind the stack, so every path in `cmd_assert` leaves through
        `exit(0)`/`exit(1)`/`fatal` before the ensure. Verified `Browser#close`
        does kill Chrome (`alive_after=false` in a throwaway-browser probe), so
        the line stayed a latent hazard rather than a live bug.
      - Green: the dead close (and the now-unused `browser` binding) is gone, so
        a later refactor from `exit` to `return` cannot start shutting down the
        user's Chrome; a comment records Go's contract.
      - Coverage: the session survives an assert (throwaway browser, then
        `title` still works), the full output matrix (`pass`; equality failure
        with `%q` quoting; `--message`/`-m` wrapping; `0`, `false`, and `null`
        truthy failures with their exit 1), and the usage fatal for no
        expression and for an empty one.
      - Ledger: `cmdAssert` → `ported`.
- [x] **Give the AX commands Go's flags and errors** — the three commands'
      usage lines named the concatenated commands (`webb axtree`, `axfind`,
      `axnode`) where Go says `ax-tree`/`ax-find`/`ax-node`, `--depth abc`
      answered `invalid depth value` instead of Go's `invalid depth: <cause>`,
      `ax-node` let a lookup failure escape as an unhandled exception (exit 1)
      instead of Go's `fatal("%v", err)` (exit 2), and the tree/lookup failures
      had no Go fatal at all.
      - Red: `ax-tree --depth abc` → `invalid depth value`; `ax-find --bogus` and
        `ax-node` (no selector) printed `axfind`/`axnode` in the usage line.
      - Green: usage lines now use the hyphenated names, the depth parse wraps
        its own error, `ax-tree` fatals with `failed to get accessibility tree:
        <cause>`, `ax-find` with `query failed: <cause>`, and `ax-node` fatals
        with `getAXNode`'s message. `Webb.get_ax_node` now carries Go's per-step
        prefixes (`element not found`, `failed to describe DOM node`, `failed to
        get accessibility info`, `no accessibility node found for selector %q`)
        instead of guessing from the message text, and `query_ax_nodes` splits
        `failed to get document` from `accessibility query failed`.
      - Kept divergence: `webb axtree`/`axfind`/`axnode` still work as aliases
        (Go rejects them as unknown commands). They are not advertised; only
        the usage text changed.
      - Coverage: `cli_spec.cr` exercises the tree (plain and `--json`), find by
        name/role/JSON/no-match/unknown flag, and ax-node detail/JSON/usage/
        missing element (under `ROD_TIMEOUT=0.5`); `webb_spec.cr` gains a table
        for `axValueStr` (nil, string, number, boolean, object).
      - Ledger: `cmdAXTree`, `cmdAXFind`, `cmdAXNode`, and `axValueStr` →
        `ported`.
- [x] **Give `title` Go's page-info error contract** — `cmd_title` printed
      `page.info`'s result, so a `Target.getTargetInfo` failure escaped as an
      unhandled exception (exit 1 with a stack trace) where Go fatals with
      `failed to get page info: <cause>` (exit 2, `main.go:630-637`). A closed
      target disappears from `pages` and racing `Target.closeTarget` is not
      reliable, so the failure cannot be forced from the CLI.
      - Green: `Webb.page_info(page)` wraps the exception with Go's prefix (the
        same per-step shape as `get_ax_node`) and `cmd_title` routes it through
        `Webb.fatal`, matching the other ported commands.
      - Coverage: `spec/webb_spec.cr` → `.page_info` asserts the live title and
        the wrapped message using a `Rod::Page` subclass whose `info` raises
        (the `lib/rod/spec` stub pattern); `spec/cli_spec.cr` keeps the live
        title example honest.
      - Ledger: `cmdTitle` → `ported`.
- [x] **Give `url` the same page-info error contract** — `cmd_url` still called
      `page.info` directly, so the failure `cmdTitle` had just learned to wrap
      escaped here as an unhandled exception (exit 1 + stack trace) where Go
      fatals with `failed to get page info: <cause>` (exit 2,
      `main.go:621-628`).
      - Green: `cmd_url` now uses the `Webb.page_info` seam and `Webb.fatal`,
        exactly like `cmd_title`.
      - Coverage: the existing `spec/cli_spec.cr` example ("prints the title and
        URL of the active page") keeps the happy path; `.page_info` already
        covers the wrapped failure.
      - Ledger: `cmdURL` → `ported`.
- [x] **Give `pages` Go's per-step errors and `(unknown)` fallback** —
      `cmd_pages` wrapped its whole body in one bare `rescue`, so a state,
      connect, or listing failure all became `failed to list pages` with no
      cause, and a page whose `Info()` failed aborted the listing instead of
      printing `(unknown)` as Go does (`main.go:1195-1220`).
      - Red: `webb pages` against a stale state printed `error: failed to list
        pages`; `.page_info?` and `.format_page_list` did not exist.
      - Green: `Webb.page_info?` mirrors Go's ignored `Info()` error,
        `Webb.format_page_list` renders the `*` marker, Go's marker-plus-space
        inactive prefix, and the `(unknown)` fallback, and `cmd_pages` fatals per
        step (`%v` for state/connect, `failed to list pages: <cause>` for the
        listing).
      - Coverage: missing, corrupt, and unreachable state; a one-page listing
        with marker, title, and URL; the active marker moving to page 1 after
        `newpage`; and unit examples for `.format_page_list`/`.page_info?` using
        stub pages that return or raise their `TargetInfo`.
      - Ledger: `cmdPages` → `ported`.
- [x] **Give `page` Go's per-step errors and conditional output** — the plan
      said `webb page abc` switched to index 0; that was wrong, because
      `"abc".to_i` raises in Crystal (unlike Ruby), so the existing
      `rescue ArgumentError` already exited 2. The real gaps: it printed
      `invalid index: abc` without the parser's cause, a bare `rescue` collapsed
      every other failure into `failed to switch page`, and the switch line read
      `page.info` unconditionally where Go prints only when `Info()` succeeds.
      - Red: a stale `debug_url` printed `error: failed to switch page` instead
        of the connect cause.
      - Green: parse with `to_i32` and fatal `invalid index: <cause>` (the
        `--depth`/`seconds` convention), fatal per step (`%v` for connect,
        `failed to list pages: <cause>`, `failed to save state: <cause>`), and
        print `Switched to [%d] %s - %s` only through `Webb.page_info?`.
      - Coverage: non-numeric index before any session, usage, out of range
        (`page index 3 out of range (0-0)`), switching 0 then 1 with the saved
        active page, and an unreachable browser. The `failed to save state`
        branch has no spec: this exFAT volume ignores `chmod`, so the write
        cannot be forced to fail deterministically.
      - Ledger: `cmdPage` → `ported`.
- [x] **Give `newpage` Go's per-step errors and conditional output** — a bare
      `rescue` turned every failure of `cmd_new_page` into
      `failed to create new page`, so a stale `debug_url` lost the connect cause,
      `save_state` was unchecked, and the `Opened` line read `page.info`
      unconditionally where Go prints only when `Info()` succeeds
      (`main.go:1253-1291`). The happy path already matched: schemeless hosts get
      `http://`, an empty argument opens `about:blank`, `wait_load` runs only for
      a real URL, and the new index is found by target id.
      - Red: a stale `debug_url` printed `error: failed to create new page`.
      - Green: connect fatal `%v`, the index lookup keeps Go's ignored
        `Pages()` error (`pages, _ :=`) so a listing failure leaves
        `ActivePage` untouched, `failed to save state: <cause>`, and the
        `Opened [%d] %s` line prints through `Webb.page_info?`.
        `MustPage`/`MustWaitLoad` failures escape as exceptions, the treatment
        every Go Must* call gets here.
      - Coverage: a blank page with no argument, a schemeless fixture URL,
        the new page becoming active (checked against `state.json` and the
        `pages` marker), and an unreachable browser.
      - Ledger: `cmdNewPage` → `ported`.
- [x] **Give `closepage` Go's per-step errors and clamp order** — the bare
      `rescue` answered `failed to close page` for a stale `debug_url` (or a
      listing failure), the index parse lost the parser's cause, and
      `save_state` was checked where Go ignores the error (`main.go:1297-1335`).
      - Red: a stale `debug_url` printed `error: failed to close page`.
      - Green: per-step fatals (`%v` connect, `failed to list pages: <cause>`),
        `to_i32` with `invalid index: <cause>`, Go's `page index %d out of
        range` without a range suffix, the len-2-then-0 clamp order, and
        `save_state` failure ignored as upstream does.
      - Coverage: last-page refusal (also before an index parse, matching Go's
        order), closing page 0 of two with the adjusted active index in
        `state.json`, out of range, non-numeric index, and an unreachable
        browser.
      - Ledger: `cmdClosePage` → `ported`.
- [x] **Give `back` Go's conditional URL output** — `cmd_back` printed
      `page.info.url` unconditionally, so a page that could not report its info
      escaped as an unhandled exception where Go prints nothing and exits 0
      (`info, _ :=`, `main.go:571-579`).
      - No red was reachable through the CLI (a closed target disappears from
        `pages`), so the characterization went in first: open `/`, open
        `/second`, `back` prints `/` — green before and after.
      - Green: the `puts` now runs only when `Webb.page_info?` returns info, the
        same seam `title`/`url` use for their fatal side.
      - Ledger: `cmdBack` → `ported`.
- [x] **Give `forward` the same conditional URL output** — `cmd_forward` was
      `cmd_back`'s untouched twin: it printed `page.info.url` unconditionally,
      so an info failure escaped as an unhandled exception where Go prints
      nothing and exits 0 (`info, _ :=`, `main.go:581-589`).
      - No red was reachable through the CLI for the same reason as `back`, so
        the characterization went in first: open `/`, open `/second`, `back`
        prints `/`, then `forward` prints `/second` — green before and after.
      - Green: an `if info = Webb.page_info?(page)` guard around the `puts`,
        matching `cmd_back` line for line.
      - Ledger: `cmdForward` → `ported`.
- [x] **Give `reload` Go's `reload failed:` fatal** — `cmd_reload` sent the
      `--hard` branch's `Page.reload{ignoreCache:true}` bare, so a failed CDP
      call escaped as an unhandled exception where Go prints
      `error: reload failed: <cause>` and exits 2
      (`main.go:596-600`). Only the hard branch is checked upstream; the plain
      branch is `page.MustReload()`.
      - No red was reachable (a live page's session is already proven before the
        command runs, and upstream has no test for this branch at all), so the
        characterization went in first: `reload` prints `Reloaded`, and
        `reload --hard` prints `Reloaded` **and really navigates** — a
        `data-marker` set before it is gone after. Green before and after.
      - Green: `begin`/`rescue ex`/`Webb.fatal("reload failed: #{ex.message}")`
        around the hard-branch call, leaving `page.reload` unguarded as Go
        leaves `MustReload`.
      - Ledger: `cmdReload` → `ported`.
- [x] **Give `clear-cache` Go's `clear cache failed:` fatal** —
      `cmd_clear_cache` sent `Network.clearBrowserCache` bare, so a failed call
      escaped as an unhandled exception where Go prints
      `error: clear cache failed: <cause>` and exits 2 (`main.go:613-615`).
      - No red was reachable (the session is proven before the command runs, and
        upstream has no test for this command), so the characterization went in
        first: `clear-cache` prints `Browser cache cleared`, and the page is
        still usable afterwards (`title` still answers). Green before and after.
      - Green: `begin`/`rescue ex`/`Webb.fatal("clear cache failed: …")`
        around the CDP call.
      - Ledger: `cmdClearCache` → `ported`.
- [x] **Give `html` Go's error wrapping** — `cmd_html` looked up the element
      and read its HTML bare, so a selector that matched nothing escaped as an
      unhandled exception (exit 1) where Go prints
      `error: element not found: <cause>` and exits 2, then checks
      `el.HTML()` separately for `failed to get HTML: <cause>`
      (`main.go:638-655`).
      - Red was real this time: `html "#missing"` exited **1** (expected 2) —
        the failing example is what drove the change.
      - Green: two `begin`/`rescue ex`/`Webb.fatal` blocks, the same shape
        `cmd_attr` uses for its element lookup. The no-selector branch stays on
        `page.eval("() => document.documentElement.outerHTML")`.
      - Coverage: document HTML (no selector), an element's outer HTML, and the
        missing selector with `ROD_TIMEOUT=0.5` pinning
        `error: element not found: context deadline exceeded` at exit 2.
      - Ledger: `cmdHTML` → `ported`.
- [x] **Give `text` Go's error wrapping** — `cmd_text` guarded only the usage
      case, so `page.element` and `el.text` escaped as an unhandled exception
      (exit 1) where Go prints `error: element not found: <cause>` and exits 2,
      then checks `el.Text()` for `failed to get text: <cause>`
      (`main.go:657-670`).
      - Red was real: `text "#missing"` exited **1** (expected 2).
      - Green: the same two `begin`/`rescue ex`/`Webb.fatal` blocks as `html`.
      - Coverage: `text "#topic"` prints the select's selected option text
        (`General`, rod's `text` helper joins `selectedOptions`), the usage line
        with no argument, and the missing selector with `ROD_TIMEOUT=0.5`
        pinned to `error: element not found: context deadline exceeded`.
      - Ledger: `cmdText` → `ported`.
- [x] **Give `js` Go's `JS error:` fatal** — `cmd_js` evaluated the wrapped
      expression bare, so a throwing expression escaped as an unhandled
      exception (exit 1) where Go prints `error: JS error: <cause>` and exits 2
      (`main.go:722-728`).
      - Red was real: `js "nope()"` (a `ReferenceError` at runtime, valid
        syntax inside Go's `() => { return (expr); }` wrapper) exited **1**
        where the spec wants 2.
      - Green: `begin`/`rescue ex`/`Webb.fatal("JS error: …")` around
        `page.eval`, leaving `Webb.format_js_result` for the value switch.
      - Coverage: `1 + 1` → `2`, `'hi'` → `hi`, `null` → `null`,
        `true` → `true`, `({a: 1})` → two-space pretty JSON, and a throwing
        expression asserting Go's prefix with no `Unhandled exception` line.
        The detail text after the prefix comes from rod's `EvalError`, as it
        does from Go's rod.
      - Ledger: `cmdJS` → `ported`.
