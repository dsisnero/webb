# History — Ledger and discovery tooling

> Completed work on the parity ledger and the tree-sitter gates. The ledger
> itself is the current state; this file records how it got its shape. The one
> open item (re-basing on a pin change) lives in `plans/parity.md`.

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
