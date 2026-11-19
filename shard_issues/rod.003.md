# rod.003: managed-browser download noise and layout

**Shard:** `lib/rod` (`dsisnero/rod`)
**Priority:** Low
**Type:** behavior gap + environment interaction

Two gaps showed up once `cmd_start` actually launched Chrome. The first was
fixed upstream in `1f7636a`; the second is an interaction with this repo's
exFAT volume.

## 1. Launch log on stdout (resolved upstream)

`Launcher` used to bind `@logger = ::Log.for("rod.launcher")` and emit
`@logger.info { "Launching browser: ..." }` inside `launch`. Crystal's default
`Log` backend writes INFO to **stdout**, so `webb start` printed a leading
`INFO - rod.launcher: Launching browser: ...` line that go-rod never produces
(its `logger` field is `io.Discard`, and `Launcher.Logger(w)` only forwards the
browser's own stdout/stderr).

Fixed in `dsisnero/rod` `1f7636a` ("port: launcher output contract (no launch
log, real logger(io))"): the `::Log` property is gone, `logger(io : IO)` is the
only sink API (defaulting to discard), and the launcher no longer logs the
launch. `cmd_start` therefore carries **no** logger workaround; the CLI prints
Go's two lines by itself.

That commit is not tagged yet, so `shard.yml` tracks `branch: main` and
`shard.lock` pins `0.7.0+git.commit.1f7636a...`. Drop `branch: main` once a tag
contains the fix.

### Remaining: the downloader still logs at INFO

`Browser#download` (`lib/rod/src/rod/util/launcher.cr`) still emits
`@logger.info { "Trying to download from ..." }` / `"Successfully downloaded"`
through `@logger = ::Log.for("rod.launcher")`, which lands on stdout. go-rod's
`Browser` hands `fetchup` a nil logger, so it logs nothing.

This only shows up on the managed-download path, which currently fails anyway
(item 2), and no CLI spec exercises it — the harness always passes
`ROD_CHROME_BIN`. Not worked around; whoever fixes `Browser` should drop those
INFO calls (or give `Browser#logger` the same discard default as
`Launcher#log_io`).

## 2. `strip_first_dir` is skipped on an exFAT volume

`Browser#bin_path` resolves to `<dir>/Chromium.app/Contents/MacOS/Chromium`.
The macOS snapshot (`chrome-mac.zip`) extracts to
`<dir>/chrome-mac/Chromium.app/...`, and `Browser#download` calls
`strip_first_dir(dir)` at the end — the port of go-rod's
`fetchup.StripFirstDir` — to remove that top-level folder.

`strip_first_dir` starts with:

```crystal
entries = Dir.children(dir)
return unless entries.size == 1
```

macOS writes AppleDouble sidecars (`._chrome-mac`) next to extracted files on
exFAT. The directory then holds **two** entries, the guard returns early, no
strip happens, and the launch fails with
`No such file or directory .../chromium-<rev>/Chromium.app/Contents/MacOS/Chromium`.
On APFS/HFS+ the same download works.

This is why `spec/cli_spec.cr` always passes `ROD_CHROME_BIN` (also the
documented upstream override), so the suite never touches the managed download.

### Reproduction

```bash
rm -rf temp/manual && mkdir -p temp/manual
env -i HOME=$PWD/temp/manual RODNEY_HOME=$PWD/temp/manual ./bin/webb start
```

`~/.cache/rod/browser/chromium-<rev>/` then contains `chrome-mac` and
`._chrome-mac`, while the launcher looks for `Chromium.app` one level up.

### Fix

Optional, and only worth doing if the shard is expected to run on exFAT
volumes: make `strip_first_dir` ignore `._*` entries (or strip when exactly one
*non-sidecar* entry is a directory) before `Browser#get` validates `bin_path`.
go-rod has the same strictness, so this is a host-environment shim rather than
a parity gap. `make clean` does not reach into `~/.cache/rod`, so a stale
`chromium-<rev>` directory must be removed by hand after a failed attempt.
