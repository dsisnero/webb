# Changelog

All notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`webb` is a Crystal port of [Rodney](https://github.com/simonw/rodney), and the
Go source in `vendor/rodney` is the behavior contract. Entries here describe the
port and its shard, not upstream releases: every command, flag, output line,
exit code, and error string matches upstream `v0.4.0` (`9e7ae93`) except the
documented [differences](README.md#differences-from-rodney).

## [Unreleased]

### Changed

- Moved the `rod` pin from `7063829` to `04403b0` (`shards update rod`).
  Sixteen upstream commits, no CLI change needed; the suite stayed green.
  Element-level CDP requests (`describe`, `shape`, `scroll_into_view`,
  `set_files`, `shadow_root`) now carry the element's own context, a refreshed
  `<iframe>` element stays on the parent page, `interactable` reports a failed
  coverage check as an error again instead of swallowing Chrome's cross-JS-world
  message, `input_time`/`input_color`/`contains_element` evaluate go-rod's
  shared JS helpers, `Element#screenshot` always sends `quality` and omits an
  empty `format`, `Browser#page` forwards go's creation options, and `pdf`'s
  stream close surfaces CDP errors while keeping a chunk that arrives with
  `eof`. Pin history: [plans/history-shard.md](plans/history-shard.md).

## [0.1.0] - 2026-11-23

First complete port of Rodney `v0.4.0` (`9e7ae93`): 43 public commands plus the
hidden `_proxy` helper, with upstream's flags, output, exit codes, and error
text. Every curated row in the parity inventory is `ported` or a documented
divergence.

### Added

- **Browser lifecycle:** `start` (headless Chrome by default, `--show` for a
  visible window, `--insecure`/`-k` to ignore certificate errors), `connect` to
  an existing debug port, `stop`, and `status`. `start` prints upstream's two
  lines and leaves Chrome running after the CLI exits.
- **Navigation:** `open`, `back`, `forward`, `reload` (`--hard` bypasses the
  cache), and `clear-cache`.
- **Page info:** `url`, `title`, `html` with an optional selector, `text`,
  `attr`, and `pdf`.
- **Interaction:** `js`, `click`, `input`, `clear`, `select`, `submit`,
  `hover`, `focus`, `file` (a path, or `-` for stdin), and `download` (`-` for
  stdout, otherwise a filename inferred from the URL path, or the MIME type for
  `data:` URLs).
- **Waiting:** `wait` for an element, `waitload`, `waitstable` (upstream's
  one-second `MustWaitStable`), `waitidle`, and `sleep`.
- **Screenshots:** `screenshot` with `-w`/`-h` viewport sizing (full page by
  default) and `screenshot-el` for an element's box.
- **Tabs:** `pages`, `page`, `newpage`, and `closepage`.
- **Element checks:** `exists`, `visible`, `count`, and `assert` (truthy or
  equality with `-m`), each with upstream's exit-code contract.
- **Accessibility:** `ax-tree` (`--depth`), `ax-find` (`--name`, `--role`), and
  `ax-node`, with `--json` output and upstream's tree formatting.
- **Sessions:** global state in `~/.rodney/`, directory-scoped `--local` state
  in `./.rodney/`, auto-detection between them, and the `RODNEY_HOME` override.
- **Authenticated proxies:** `start` detects proxy credentials from
  `HTTPS_PROXY`/`HTTP_PROXY` and their lowercase forms, launches the local
  forwarding helper, and cleans it up on `stop`; plain HTTP and `CONNECT`
  tunneling both work.
- **Parity tooling:** tree-sitter inventory gates (`make inventory`) over the
  pinned upstream source, the curated ledger in
  [plans/inventory/](plans/inventory/), and `make parity-verify` against the
  installed parity skill.

### Compatibility notes

- Output and failure text follow Go, including `*PathError` phrasing for OS
  failures in `file`/`pdf`/`download`/`screenshot` and SIGPIPE tolerance, so
  `webb ... | head` exits like upstream.
- Seven intentional divergences are documented in the README: the binary name,
  `start --show`, the unadvertised `axtree`/`axfind`/`axnode` aliases, relative
  upload paths, closed-stdout status, the `_proxy` detach without `Setsid`, and
  Go-shaped `File.write` causes.

### Tests

- 239 examples (100 library, 139 CLI harness: 22 process contracts, 3 `_proxy`,
  4 `start` session, and 110 live-browser) against a real Chrome via
  `ROD_CHROME_BIN`, all ported from upstream's tests or characterization specs
  written where upstream's assertions could not survive translation.
