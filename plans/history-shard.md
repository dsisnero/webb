# History — `dsisnero/rod` pin and shard fixes

> webb tracks rod `branch: main` and moves the pin when a fix it needs lands.
> Current pin: `0b42a3a` (see `shard.lock`). This file records why each pin
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

## Latest pin adoption (`0b42a3a`)

- Moved from `04403b0` to `0b42a3a` with `shards update rod`. Three upstream
  commits, no webb code change needed: the whole suite stayed green (239
  examples).
  - `0b42a3a` adds the remaining `!` aliases —
    `Rod::Util::Launcher.resolve_url!` / `new_managed!` (module-level, because a
    macro cannot have a receiver), `Launcher#client!`, and `Pool#get!`, which
    forwards a creation block that `method_missing` cannot. Additive: every
    alias routes to the same `must_*` helper, so error handling and
    `trace(true)` output are unchanged. webb calls no `must_*` method at all (it
    uses the non-bang methods and renders Go's messages from rescued errors), so
    the aliases are simply unused here.
  - `d19cb3b` rewrites the shard's 30 examples to the `!` spelling. Examples are
    not on webb's path.
  - `5b03818` narrows the shard's example rebuild triggers to each example's
    own sources plus `src/**/*.cr`. Build tooling only.
- Verification: `make format`, `make lint` (5 files, 0 failures), `make test`
  (239 examples, 0 failures, 0 pending), `make build`, `make inventory`
  (tree-sitter), `make parity-verify`, and `make docs-lint` all pass on the new
  pin.

## Previous pin adoption (`04403b0`)

- Moved from `7063829` to `04403b0` with `shards update rod`. Sixteen upstream
  commits, no webb code change needed: the whole suite stayed green (239
  examples) because the touched paths are already covered here.
  - Element request plumbing (the commands webb's `el`, `attr`, `scroll`,
    `input file`, `click`, and `hover` ride on):
    - `ffad909` makes `Element` a `Cdp::Client`, so `describe`, `shape`,
      `scroll_into_view`, `set_files`, and `shadow_root` carry the element's own
      context instead of the page's — an element cloned with `#timeout` now
      has its deadline reach those requests.
    - `6f15d6e` keeps a refreshed `<iframe>` element on the **parent** page, so
      its object handle and injected `lib/js` helpers stay in one JS world after
      go's stale-node retry.
    - `eaf4b82` returns the `ContainsElement` result from `interactable` again
      instead of special-casing Chrome's "Argument should belong to the same
      JavaScript world" message: the wrong-world bug behind that message is
      gone, so a failed coverage check is raised as `CoveredError` (and retried
      by `wait_interactable`) like go's `Interactable`.
    - `fb1b165` evaluates go's shared JS helpers for `input_time`,
      `input_color`, and `contains_element` (`element.go:303`, `325`, `475`);
      `input_time` regains its user gesture, and all 33 helpers in
      `src/rod/util/js.cr` are now wired, so a helper edit cannot leave a stale
      inline copy behind.
    - `3664c94` races `Element#wait_stable` between a ticker and the element
      context (and traces `stable` only after `WaitVisible`), matching
      `element.go:519-550`. webb only waits at the page level, so this is inert
      here but keeps element timeouts honest.
  - Wire payloads:
    - `85aef71` always sends `quality` on `Element#screenshot` (go's
      `gson.Int(0)`) and omits an empty `format`, which is what `screenshot-el`
      puts on the wire.
    - `66f072b` enables `DOMSnapshot` and sets go's four include flags
      (`includePaintOrder`, `includeDOMRects`, `includeBlendedBackgroundColors`,
      `includeTextColorOpacities`); rodney never calls it, so this is inert.
    - `202b6c9` adds `Browser#page(opts : Cdp::Target::CreateTarget)` forwarding
      go's creation options. webb still creates pages by URL (`start`, `open`),
      which keeps its previous semantics.
  - `ca27a6b` returns `StreamReader#close`'s CDP error and serves a buffered
    chunk that arrives with `eof: true` — the `pdf` path. `must_pdf` still
    ignores a close failure, like go's `MustPDF`.
  - `d1be487` traces the six page waits at go's `tryTrace` sites
    (`event`, `request-idle`, `dom-stable`, `stable`, `wait open`,
    `navigation`) and drops `Element#wait`'s invented span. webb has no trace
    flag, so nothing user-visible changes.
  - Shard-only hygiene: `7111045`, `5358a19` (examples repaired, `make
    check-examples`, docs), `8b8ee0f` (incremental `make examples`), `a1592e1`
    (plain example output, `trace(true)` in `compare-chromedp/click`),
    `3c8a821` and `04403b0` (parity hand-off docs).
- Verification: `make format`, `make lint` (5 files, 0 failures), `make test`
  (239 examples, 0 failures, 0 pending), `make build`, `make inventory`
  (tree-sitter), `make parity-verify`, and `make docs-lint` all pass on the new
  pin.

## Earlier pin adoption (`7063829`)

- Moved from `1567742` to `7063829` with `shards update rod`. Nine upstream
  commits, no webb code change needed: the whole suite stayed green (239
  examples) because the touched paths are already covered here.
  - `d9b1431` gates `src/cdp` against the pinned generation (shard-only gate
    script and docs).
  - `d4de3b0` waits for the root repaint before scrolling an element, which the
    `click`, `hover`, and `screenshot-el` paths ride on.
  - `ee1e789` drops go-rod's dev-helper trace overlays, so screenshots and
    dev-helper output match upstream again.
  - `94e5e08` listens for expose bindings and omits false capture flags;
    flagged `screenshot` options no longer send `captureBeyondViewport=false`.
  - `72f43f6` omits false `eval` flags like go's `omitempty`, which changes what
    `evaluate` puts on the wire for `userGesture`/`awaitPromise`.
  - `344a9ba` runs element operations in the element's own context (8 call
    sites), matching go's `el.page.Context(el.ctx)`.
  - `b664677` and `0e1ebbd` restore event domains through the state registry
    (`EnableDomain`), so `wait`, `waitidle`, `waitload`, `waitstable`,
    `assert`, `HandleAuth`, `set-extra-headers`, and dialog handling stop
    disabling domains another caller enabled.
  - `7063829` dispatches `input`/`change` through go's `InputEvent` helper with
    `.by_user`, so `webb input`/`clear` fire inside a user gesture.
- Verification: `make format`, `make lint`, `make test` (239 examples, 0
  failures), `make build`, `make inventory` (tree-sitter), `make parity-verify`,
  and `make docs-lint` all pass on the new pin.

## Oldest pin adoption (`1567742`)

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
