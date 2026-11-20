# History — `dsisnero/rod` pin and shard fixes

> webb tracks rod `branch: main` and moves the pin when a fix it needs lands.
> Current pin: `1567742` (see `shard.lock`). This file records why each pin
> mattered; `plans/parity.md` has the current pin and gotchas.

## `waitstable` and `start` gaps (closed)

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

## Idle-counter cancellation (closed)

- Found in `lib/rod` while proving it: `IdleCounter#wait`
  (`src/rod/util/utils.cr`) used `ctx.done.receive` in its `select`, and a
  cancelled context *closes* that channel, so the fiber `wait_request_idle`
  spawns died with `Channel::ClosedError` and printed
  `Unhandled exception in spawn` on the CLI's stderr (any `waitstable` or
  `waitidle` run could hit it). Fix prepared with a red → green spec in
  the shard: `ctx.done.receive?` in that branch plus a spec
  (`spec/utils_sleeper_spec.cr`), landed as rod `7356dd8`.

## Later pin adoptions

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

## `select_all_text` (closed)

- Found while porting `input`'s happy path: `webb input "#search-form input"
  "hello there"` on a field holding `hi` produced `hello therehi`. `lib/rod`'s
  `Element#select_all_text` built a document Range (`window.getSelection()` +
  `range.selectNodeContents(this)`), which never covers `<input>`/`<textarea>`
  contents, so `InsertText` landed at the caret. Go rod evaluates
  `js.SelectAllText` (`function(){this.select()}`) as a user gesture.
- The shard already shipped that helper (`Rod::JS::SELECT_ALL_TEXT`) and just
  called a hand-rolled range instead. Filed as `shard_issues/rod.004.md` with
  the repro, the cause proof (`document.querySelector(...).select()` through
  `webb js` first makes the value replace), and the patch sketch; the file is
  deleted now that the gap is closed, matching how rod.001-003 were retired.
- Landed in `dsisnero/rod` as `35d540d`, adopted by moving `shard.lock`.
  `webb clear` was blocked by the same method, so it could never empty a field.
- Proof here: `spec/cli_spec.cr` → "replaces the field value like
  MustSelectAllText" (un-pended) asserts the field reads back `hello there`,
  and "clears an element's value" asserts the field reads back empty. With the
  old pin both fail (`hello therehi`, and the untouched `hi`).
- Ledger: `cmdInput` and `cmdClear` → `ported`.

## Latest pin adoption (`1567742`)

- Moved from `35d540d` to `1567742` with `shards update rod`. Nine upstream
  commits, no webb code change needed: every touched path was already exercised
  by the suite, which stayed green (239 examples).
  - `76b1db9` restores the fetch domain after `HandleAuth`, so an authenticated
    `start` keeps intercepting requests the way go-rod does (`CLI auth proxy`
    CONNECT examples still pass).
  - `1aa85f3` keeps caller-enabled CDP domains across event waits; `waitload`,
    `waitstable`, `waitidle`, and `assert` rely on that event plumbing.
  - `eb7b88f` reads `LoadState` params and restores the browser viewport, which
    is the path `start`, `open`, and the screenshot viewport override use.
  - `974bd28`, `1ba3793`, `7b02393`, `68fa9cd`, and `1567742` move element
    queries, ancestor walks, xpath evaluation, iframe panic handling, and quad
    geometry onto go-rod's own JS helpers and `Cdp::DOM` types. Those feed
    `element`, `click`, `hover`, `input`, `focus`, `screenshot-el`, and the
    download/attribute lookups.
  - `c2c9436` is docs-only in the shard.
- Verification: `make format`, `make lint`, `make build`, `make test` (239
  examples, 0 failures), `make inventory` (tree-sitter), and
  `make parity-verify` all pass on the new pin; `make docs-lint` clean.
