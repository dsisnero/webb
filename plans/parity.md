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

- **Current focus:** the port is feature-complete against the pin — every
  curated row is `ported` or an intentional divergence, and `cmdOpen`'s ignored
  errors now match upstream. The rod pin advanced to `7063829` (nine upstream
  commits: context/domain/event-helper fixes) with no webb code change needed.
  Nothing is queued except pin-driven work.
- **Next up (in order):**
  1. Ledger re-base when `vendor/rodney` moves off `v0.4.0`.
  2. Optional: a Chrome-through-the-proxy example against a real HTTPS origin
     (`_proxy` is proven at the socket level today).
- **Status by area:**
  - `src/webb.cr` (state, asserts, accessibility, downloads): ported.
  - `src/cli.cr` (command implementations): ported command-by-command,
    including `--insecure` over a self-signed HTTPS origin.
  - `spec/webb_spec.cr`: 100 examples. `spec/cli_spec.cr`: 139 examples (22
    process-contract, 3 `_proxy`, 4 `start` session, 110 live-browser). Suite
    total: 239 examples, 0 pending, 0 failures.
  - Curated ledger: 145 rows across 82 source declarations and 63 upstream
    tests. All 78 function IDs have Crystal references: **76 `ported`, 0
    `partial`, 2 `intentional_divergence`**. The pin has no receiver method IDs.
    All 63 upstream test rows are `ported`; no test row is `partial`.
  - Source manifest: 83 declarations at `v0.4.0` (1 class, 3 constants, 78
    functions, 1 type). Implementation statuses live in the curated ledger;
    `scopeMode` still needs a curated type mapping.
  - Docs: `README.md` and `docs/*.md` re-verified against the built CLI on
    2026-11-20 (every example captured from a live session; README borrows the
    upstream README's wording and adds the verified sample output). `rumdl
    check README.md docs/` is clean.
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
  - `shard.yml` tracks rod `branch: main` (locked at `7063829`) because the
    fixes this repo needs are not tagged yet. Go back to tag tracking when a
    release contains them; the pin history is in `plans/history-shard.md`.
  - `webb axtree`/`axfind`/`axnode` still work as unadvertised aliases (Go
    rejects them as unknown commands); the usage text uses Go's hyphenated
    names.
  - OS-error fatals (cmdFile's stat branch and the wrapped `File.write` fatals
    in `pdf`, `download`, and `screenshot`) print Go's `*PathError` text through
    `Webb.go_path_error` (`stat <path>: no such file or directory`). Do not
    revert to `ex.message` there: Crystal's phrasing is
    `Unable to get file info: '<path>': No such file or directory`.
  - Suite runtime tracks host load (`uptime`): ~40 s idle, minutes at load > 20.
    Chrome launch retries three times because it intermittently loses the
    debug-URL race under load.
- **Last port commit:** `port: match cmdOpen's ignored upstream errors`
  (`1ad7a6e`).
- **Gates (2026-11-20, rod `7063829`):** `make format`, `make lint` (5
  files), `make test` (239 examples), `make build` (CLI), `make inventory`
  (82 curated / 83 source / 63 tests on `chiasmus-tree-sitter` v0.3.4),
  `make parity-verify` (`PARITY_SKILL_VERIFIED=1`), and `make docs-lint` all
  passed on the latest shard pin.

## How features are sliced

Each checklist item below is **one feature = one commit**, sized so it:

1. changes one behavior area only — one CLI flag, one command, one harness
   piece, one ledger migration;
2. lands its spec in the same commit (red → green), never after;
3. updates the ledger rows for that behavior only, then runs `make inventory`;
4. stays reviewable in one sitting and revertible on its own.

If an item needs a second area, split it into two items instead of widening it.
Do not batch items: a commit that closes two checkboxes is two features.

## Queue

No per-row work is queued: every ledger row is either `ported` or an
intentional divergence. The next feature comes from the next `vendor/rodney`
pin (re-base the ledger first, per the hygiene item) or from the optional proxy
example; `plans/history-cli.md` records how each closed block got there.

Gates first, always:

```bash
make format && make lint && make test && make build && make inventory
```

Known flakes, not regressions: `waitstable`'s timing example
(`waits about a second for DOM stability`), the `wait` late-element example
(its 2s reveal can beat a heavily loaded `open`), and the `download`/`file`
browser parity examples fail under host load and pass on a re-run or in
isolation. A live example can also lose Chrome's debug-URL race on the first
run of `make test` and pass on the second. Check `uptime` before believing a
red.

## Open ledger hygiene

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
- A broken stdout is silent but exits 0: Crystal raises `IO::Error` on an EPIPE
  write, so `src/main.cr` turns it into `exit 0` instead of finishing the
  command like Go (whose ignored `fmt` errors keep the command's own status).
  Pinned by `spec/cli_spec.cr` → "finishes normally when stdout is closed, like
  Go's ignored SIGPIPE".
- `proc_unix.go::setSysProcAttr` gives Go's detached `_proxy` helper its own
  session (`SysProcAttr{Setsid: true}`). Crystal's `Process.new` has no setsid
  option, and `start_auth_proxy` spawns the helper with closed stdin and
  `/dev/null` output, so it already outlives `start`; the auth-proxy spec sees
  its PID alive after the parent exits and gone after `stop`. Residual
  difference: a signal to the parent's process group (Ctrl-C during `start`)
  reaches the helper too, where Go's Setsid shields it.
- `webb file` resolves the upload path with `File.expand_path` before handing it
  to Chrome, so a relative path works from any cwd; Go forwards `args[1]`
  verbatim and Chrome resolves it against its own process. Pinned by
  `spec/cli_spec.cr` → "sets a file input and echoes the argument" (the file
  lives in the harness workdir, which is not Chrome's cwd).
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
