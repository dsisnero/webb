# Architecture

## Stateless CLI / Persistent Browser

Each `webb` CLI invocation is a **short-lived Crystal process** that:

1. Reads session state (WebSocket debug URL, Chrome PID, active page index) from a JSON
   file on disk (`src/webb.cr:49-68` — `load_state` / `save_state` / `remove_state`)
2. Opens a new `rod` Browser connection to the same persistent Chrome instance
   (`src/webb.cr:72-77` — `connect_browser`)
3. Gets the active page, executes one command, then disconnects
4. Chrome keeps running independently; tabs persist between commands

## State Persistence

State is a `Webb::State` struct serialized as JSON (`src/webb.cr:28-47`):

| Field | Purpose |
|---|---|
| `debug_url` | WebSocket URL used to connect rod to Chrome (e.g. `ws://127.0.0.1:9222/devtools/...`) |
| `chrome_pid` | PID of launched Chrome (0 when connected to external Chrome) |
| `active_page` | Index into the browser's page list |
| `data_dir` | Chrome `--user-data-dir` path |
| `proxy_pid` | PID of auth proxy helper (0 if none) |
| `proxy_port` | Port the auth proxy listens on (0 if none) |

## Scope Modes (`src/webb.cr:93-123`)

`Webb::CLI.run` parses `--local` / `--global` flags, then `extract_scope_args` and
`resolve_state_dir` determine the state directory:

| Mode | State file | Chrome data dir |
|---|---|---|
| `--global` (default) | `~/.rodney/state.json` | `~/.rodney/chrome-data/` |
| `--local` | `./.rodney/state.json` | `./.rodney/chrome-data/` |
| Auto (no flag) | `./.rodney/state.json` if it exists, else global | Corresponding data dir |

Override the global directory with `RODNEY_HOME` env var (`src/webb.cr:88-90`).

## Key Modules

### `Webb` module (`src/webb.cr`, ~593 lines)

Pure functions that don't require the CLI arg parser:
- State CRUD, browser connection, page lookup (`with_page`)
- JS result formatting (`raw_js_result`, `format_js_result`)
- Assert logic (`parse_assert_args`, `format_assert_fail`, `cmd_assert`)
- Accessibility tree formatting (`format_ax_tree`, `query_ax_nodes`, `get_ax_node`)
- Download helpers (`decode_data_url`, `mime_to_ext`, `infer_download_filename`, `next_available_file`)
- Proxy detection (`detect_proxy`)

### `Webb::CLI` class (`src/cli.cr`, ~1129 lines)

Command implementations that parse args and call into `Webb` functions and `rod`:
- `self.run` is the main dispatcher — routes to `cmd_*` methods
- 41 subcommands organized by category: browser lifecycle, navigation, info extraction,
  interaction, waiting, screenshots, tab management, element checks, accessibility
- Exit codes: 0 = success, 1 = check failed, 2 = error

### Entry point (`src/main.cr`, 3 lines)

```crystal
require "./cli"
Webb::CLI.run(ARGV)
```

## Proxy Support (`src/cli.cr:89-111, 1016-1066`)

On `webb start`, `detect_proxy` (`src/webb.cr:564-593`) checks `HTTPS_PROXY` and
`HTTP_PROXY` for authenticated proxy URLs. If found:
1. A local Crystal HTTP server is launched as a subprocess (`_proxy` internal command)
2. The server forwards HTTP requests through the upstream proxy, injecting
   `Proxy-Authorization` headers
3. Chrome is launched with `--proxy-server` pointing to the local proxy

HTTP proxy forwarding works; HTTPS CONNECT tunneling is not yet supported
(`shard_issues/rod.001.md`, `src/cli.cr:1037` returns 501).

## Accessibility Commands (`src/webb.cr:363-543`)

Three `ax-*` commands call the Chrome DevTools Protocol Accessibility domain via rod:

| Command | CDP method | Crystal function |
|---|---|---|
| `ax-tree` | `Accessibility.getFullAXTree` | `format_ax_tree` → `walk_ax_tree` |
| `ax-find` | `Accessibility.queryAXTree` | `query_ax_nodes` |
| `ax-node` | `Accessibility.getPartialAXTree` | `get_ax_node` |

All three support `--json` for machine-readable output.

## Upstream Reference

The Go source of truth is `vendor/rodney/main.go` (1972 lines, single-file implementation
using `go-rod/rod`). All Crystal behavior must match the Go implementation documented in
`plans/inventory/go_port_inventory.tsv`.
