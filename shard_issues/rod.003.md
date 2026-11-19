# rod.003: launcher logs to stdout and its managed browser path is wrong

**Shard:** `lib/rod` (`dsisnero/rod`, local patch)
**Priority:** Low
**Type:** behavior gap + bug

## Description

Two unrelated gaps in `lib/rod/src/rod/util/launcher.cr` show up as soon as a
command actually launches Chrome (the CLI only did so once `cmd_start` was
ported).

### 1. Launch and download progress is logged at INFO on stdout

`Launcher#initialize` binds `@logger = ::Log.for("rod.launcher")` and
`Launcher#launch` emits `@logger.info { "Launching browser: ..." }`, plus
`Browser#download` emits one line per host. Crystal's default `Log` backend
writes INFO to **stdout**.

go-rod's launcher has no such log path at all: its `logger` field is
`io.Discard` and `Launcher.Logger(w)` only forwards the *browser's* own
stdout/stderr, so `rodney start` prints exactly two lines.

Upstream `cmdStart` (`vendor/rodney/main.go:426-427`) prints
`Chrome started (PID %d)` and `Debug URL: %s` and nothing else, so the shard's
INFO line breaks the CLI's output contract.

Workaround here: `Webb::CLI.cmd_start` points `launcher.logger` and
`launcher.browser.logger` at `::Log.new("rod.launcher", nil, :none)` (a logger
with no backend) before launching.

### 2. `Browser#bin_path` does not match the macOS archive layout

`Browser#bin_path` resolves to `<dir>/Chromium.app/Contents/MacOS/Chromium`,
but the macOS chromium snapshot (`chrome-mac.zip`) extracts to
`<dir>/chrome-mac/Chromium.app/Contents/MacOS/Chromium`. `Browser#get` then
downloads successfully and returns a path that does not exist, so the launch
fails with `File::NotFoundError`.

go-rod avoids this by calling `fetchup.StripFirstDir(dir)` at the end of
`Browser.Download()`, which removes the archive's single top-level folder.
`lib/rod` has no equivalent step.

Workaround here: `spec/cli_spec.cr` always passes `ROD_CHROME_BIN`, which is
also the documented upstream override, so the suite never exercises the managed
download.

## Impact

- Any command that launches Chrome prints a leading `INFO - rod.launcher: ...`
  line unless the logger is replaced.
- `webb start` without `ROD_CHROME_BIN` and without Chrome in a well-known
  location downloads ~130 MB and then fails to launch the result.

## Reproduction

```bash
rm -rf temp/manual && mkdir -p temp/manual
env -i HOME=$PWD/temp/manual RODNEY_HOME=$PWD/temp/manual ./bin/webb start
```

1. Before the fix, stdout starts with `INFO - rod.launcher: Launching browser:`
   even when `ROD_CHROME_BIN` points at a real Chrome.
2. Without `ROD_CHROME_BIN`, the download logs succeed and the launch raises
   `No such file or directory .../chromium-<rev>/Chromium.app/Contents/MacOS/Chromium`,
   while the extracted tree is `.../chromium-<rev>/chrome-mac/Chromium.app/...`.

## Fix

1. Drop the launch/download INFO logs, or route the shard's logger to a
   `Log::IOBackend` bound at `:warn` so INFO output never reaches stdout.
2. On macOS, join `bin_path` with `chrome-mac`, or port go-rod's
   `fetchup.StripFirstDir` step so the archive's top-level folder is removed
   after extraction.

Remove the `silent_logger` workaround in `cmd_start` once (1) lands, and drop
`ROD_CHROME_BIN` from the spec harness once (2) lands.
