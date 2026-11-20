# Architecture

## Stateless CLI / Persistent Browser

Each `webb` CLI invocation is a **short-lived Crystal process** that:

1. Reads session state (WebSocket debug URL, Chrome PID, active page index) from
   a JSON file on disk (`src/webb.cr` — `load_state` / `save_state` /
   `remove_state`)
2. Opens a new `rod` Browser connection to the same persistent Chrome instance
   (`src/webb.cr` — `connect_browser`)
3. Gets the active page, executes one command, then disconnects
4. Chrome keeps running independently; tabs persist between commands

`src/main.cr` is the entry point: it runs `Webb::CLI.run(ARGV)` and turns a
broken-pipe `IO::Error` into a clean exit (Go's `init()` ignores `SIGPIPE`).

## State Persistence

State is a `Webb::State` struct serialized as JSON (`src/webb.cr`):

| Field | Purpose |
|---|---|
| `debug_url` | WebSocket URL used to connect rod to Chrome (e.g. `ws://127.0.0.1:9222/devtools/...`) |
| `chrome_pid` | PID of launched Chrome (0 when connected to external Chrome) |
| `active_page` | Index into the browser's page list |
| `data_dir` | Chrome `--user-data-dir` path |
| `proxy_pid` | PID of the auth proxy helper (nil when none) |
| `proxy_port` | Port the auth proxy listens on (nil when none) |

Reads go through two functions, mirroring Go's error-return style:

- `load_state` — fatals `no browser session (run 'webb start' first)` when the
  file is missing and `corrupt state file: <cause>` when it does not parse
- `load_state?` — returns `nil` for either failure; used by `status` and
  `start`, which treat both as "no session"

`save_state` raises Go's `*PathError` text (`mkdir <dir>: <cause>` /
`open <path>: <cause>`) for the callers that fatal
`failed to save state: <cause>`. `remove_state` ignores removal errors, exactly
like upstream's unchecked `os.Remove`.

## Scope Modes (`src/webb.cr`)

`Webb::CLI.run` parses `--local` / `--global` flags, then `extract_scope_args`
and `resolve_state_dir` determine the state directory:

| Mode | State file | Chrome data dir |
|---|---|---|
| `--global` (default) | `~/.rodney/state.json` | `~/.rodney/chrome-data/` |
| `--local` | `./.rodney/state.json` | `./.rodney/chrome-data/` |
| Auto (no flag) | `./.rodney/state.json` if it exists, else global | Corresponding data dir |

Precedence matches Go's `stateDir`: **`RODNEY_HOME` wins** over both modes when
set (`state_dir` checks it before the resolved scope directory).

## Key Modules

### `Webb` module (`src/webb.cr`, ~717 lines)

Pure functions that don't require the CLI arg parser:

- State CRUD, browser connection, page lookup (`with_page`)
- State-dir resolution (`extract_scope_args`, `resolve_state_dir`, `state_dir`)
- JS result formatting (`raw_js_result`, `format_js_result`)
- Assert logic (`parse_assert_args`, `format_assert_fail`, `cmd_assert`)
- Accessibility formatting (`format_ax_tree`, `format_ax_node_list`,
  `format_ax_node_detail`, `format_properties`, `query_ax_nodes`, `get_ax_node`)
- Download helpers (`decode_data_url`, `mime_to_ext`, `infer_download_filename`,
  `next_available_file`)
- Proxy detection (`detect_proxy`)
- OS-error formatting (`go_path_error`) and the fatal writer (`fatal`)

Module load also mirrors Go's two `init` functions: `ROD_TIMEOUT` becomes
`DEFAULT_TIMEOUT`, and Crystal's `exit_on_broken_pipe` emulation is turned off
alongside `Signal::PIPE.ignore`.

### `Webb::CLI` class (`src/cli.cr`, ~1681 lines)

Command implementations that parse args and call into `Webb` functions and
`rod`:

- `self.run` is the main dispatcher — routes to `cmd_*` methods
- 43 advertised subcommands organized by category (browser lifecycle,
  navigation, info extraction, interaction, waiting, screenshots, tab
  management, element checks, accessibility) plus the hidden `_proxy` helper
- Exit codes: 0 = success, 1 = check failed, 2 = error

### Entry point (`src/main.cr`, 13 lines)

```crystal
require "./cli"

begin
  Webb::CLI.run(ARGV)
rescue ex : IO::Error
  raise ex unless ex.os_error == Errno::EPIPE

  exit 0
end
```

## Proxy Support

On `webb start`, `detect_proxy` checks `HTTPS_PROXY`, `https_proxy`,
`HTTP_PROXY`, and `http_proxy` (in that order, skipping empty values) for
authenticated proxy URLs. If found, `start_auth_proxy`:

1. Picks a free loopback port
2. Re-launches the CLI as the detached `_proxy` helper with closed stdin and
   `/dev/null` output, passing the upstream server and a `Basic` auth header
3. Records the helper's PID/port in `state.json`
4. Waits briefly, then launches Chrome with `--proxy-server` pointing at the
   local proxy and `ignore-certificate-errors`

HTTP proxy forwarding and HTTPS `CONNECT` tunneling both work. Go hijacks the
connection with `http.Hijacker`; Crystal's `HTTP::Server` cannot hand a
connection back, so `_proxy` serves a raw `TCPServer` itself and tunnels
`CONNECT` there (`cmd_internal_proxy`). `stop` TERMs the helper.

## Accessibility Commands

Three `ax-*` commands call the Chrome DevTools Protocol Accessibility domain via
rod:

| Command | CDP method | Crystal function |
|---|---|---|
| `ax-tree` | `Accessibility.getFullAXTree` | `format_ax_tree` → `walk_ax_tree` |
| `ax-find` | `Accessibility.queryAXTree` | `query_ax_nodes` → `format_ax_node_list` |
| `ax-node` | `Accessibility.getPartialAXTree` | `get_ax_node` → `format_ax_node_detail` |

All three support `--json` for machine-readable output. `format_ax_node_list`
omits `backendNodeId` when it is zero, matching Go's `!= 0` check.

## Error Handling

- `Webb.fatal(message)` prints `error: <message>` to stderr and exits 2,
  matching Go's `fatal` (a closed stderr is ignored so the exit code survives)
- OS failures wrapped by `file`, `pdf`, `download`, and `screenshot` go through
  `go_path_error`, which renders Go's `*PathError` text (`<op> <path>: <cause>`)
- `Must*` failures (navigation, focus, wait, load) escape as exceptions, the
  same treatment every Go `p.e` panic gets in this port
- Check commands (`exists`, `visible`, `assert`, `ax-find` with no matches)
  print their result and exit 1 without touching stderr

## Upstream Reference

The Go source of truth is `vendor/rodney/main.go` (1972 lines, single-file
implementation using `go-rod/rod`), with tests in `vendor/rodney/main_test.go`
(1150 lines) and the platform split in `proc_unix.go` / `proc_windows.go`. All
Crystal behavior must match that implementation, as recorded in
`plans/inventory/go_port_inventory.tsv`.
