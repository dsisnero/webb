# webb: Chrome automation from the command line

A Crystal port of [Rodney](https://github.com/simonw/rodney), a CLI tool that
drives a persistent headless Chrome instance using the
[rod](https://github.com/dsisnero/rod) Crystal shard (itself a port of
[go-rod/rod](https://github.com/go-rod/rod)). Each command connects to the same
long-running Chrome process, making it easy to script multi-step browser
interactions from shell scripts or interactive use.

The Go source in `vendor/rodney/` (release `v0.4.0`, commit `9e7ae93`) is the
behavior contract: commands, flags, output, exit codes, and error text all match
upstream, differing only in Crystal idioms and libraries. See
[Differences from Rodney](#differences-from-rodney) for the short, documented
list.

## Architecture

```text
webb start          →  launches Chrome (headless, persists after CLI exits)
                       saves WebSocket debug URL to ~/.rodney/state.json

webb connect H:P    →  connects to an existing Chrome on a remote debug port
                       saves WebSocket debug URL to ~/.rodney/state.json

webb open URL       →  connects to running Chrome via WebSocket
                       navigates the active tab, disconnects

webb js EXPR        →  connects, evaluates JS, prints result, disconnects

webb stop           →  connects and shuts down Chrome, cleans up state
```

Each CLI invocation is a short-lived process. Chrome runs independently and tabs
persist between commands.

A fresh headless session has **no pages** (Chrome starts with
`--no-startup-window`), so the first `webb open` creates page `0`:

```console
$ webb start
Chrome started (PID 44706)
Debug URL: ws://127.0.0.1:57671/devtools/browser/4dfcd374-...

$ webb open http://127.0.0.1:8765/
Webb Demo

$ webb status
Browser running (PID 44706)
Debug URL: ws://127.0.0.1:57671/devtools/browser/4dfcd374-...
Pages: 1
Active page: 0
Current: Webb Demo - http://127.0.0.1:8765/
```

## Documentation

- **[Resuming Work](docs/resuming.md)** — Start-of-session checklist: where we
  are, clean baseline, next feature
- **[Architecture](docs/architecture.md)** — Stateless CLI design, state
  persistence, scope modes, proxy support, accessibility commands
- **[Development](docs/development.md)** — Build targets, porting workflow,
  directory layout
- **[Testing](docs/testing.md)** — Spec structure, test categories, parity
  manifests, running tests
- **[Coding Guidelines](docs/coding-guidelines.md)** — Upstream parity rules,
  naming conventions, exit codes, Crystal patterns
- **[PR Workflow](docs/pr-workflow.md)** — Quality gates, PR template, review
  checklist, CI pipeline
- **[Changelog](CHANGELOG.md)** — Release notes: the initial port, then only
  cross-cutting changes such as shard pin moves

## Installation

1. Install Crystal (>= 1.19.1) and Shards.

2. Clone this repository with submodules:

   ```bash
   git clone --recurse-submodules https://github.com/dsisnero/webb.git
   cd webb
   ```

3. Install dependencies:

   ```bash
   shards install
   ```

4. Build the binary:

   ```bash
   crystal build src/main.cr -o webb
   ```

   Or use `make build`, which compiles the CLI to `bin/webb`.

Requires:

- Crystal 1.19.1+
- Google Chrome or Chromium installed (or set `ROD_CHROME_BIN=/path/to/chrome`)

## Usage

### Start/stop the browser

```bash
webb start              # Launch headless Chrome
webb start --show       # Launch with visible browser window
webb start --insecure   # Launch with TLS errors ignored (-k shorthand)
webb connect host:9222  # Connect to existing Chrome on remote debug port
webb status             # Show browser info and active page
webb stop               # Shut down Chrome
```

`start`/`connect` write the WebSocket debug URL and the Chrome PID to
`~/.rodney/state.json`; every other command reads it and reconnects.

### Navigate

```bash
webb open https://example.com    # Navigate to URL
webb open example.com            # http:// prefix added automatically
webb back                        # Go back
webb forward                     # Go forward
webb reload                      # Reload page
webb reload --hard               # Reload bypassing cache
webb clear-cache                 # Clear the browser cache
```

`open` prints the page title once the load finishes (silently exits 0 when the
page cannot report it); `back`/`forward` print the resulting URL.

```console
$ webb open http://127.0.0.1:8765/testfile.txt
127.0.0.1:8765/testfile.txt

$ webb back
http://127.0.0.1:8765/

$ webb forward
http://127.0.0.1:8765/testfile.txt
```

### Extract information

```bash
webb url                    # Print current URL
webb title                  # Print page title
webb text "h1"              # Print text content of element
webb html "div.content"     # Print outer HTML of element
webb html                   # Print full page HTML
webb attr "a#link" href     # Print attribute value
webb pdf output.pdf         # Save page as PDF (default: page.pdf)
```

```console
$ webb url
http://127.0.0.1:8765/

$ webb title
Webb Demo

$ webb text "h1"
Webb Demo

$ webb html "h1"
<h1>Webb Demo</h1>

$ webb attr "#link" href
/testfile.txt

$ webb pdf
Saved page.pdf (44886 bytes)
```

### Run JavaScript

```bash
webb js document.title                        # Evaluate expression
webb js "1 + 2"                               # Math
webb js 'document.querySelector("h1").textContent'  # DOM queries
webb js '[1,2,3].map(x => x * 2)'            # Returns pretty-printed JSON
webb js 'document.querySelectorAll("a").length'     # Count elements
```

The expression is automatically wrapped in `() => { return (expr); }`.

```console
$ webb js "1 + 2"
3

$ webb js '[1,2,3].map(x => x * 2)'
[
  2,
  4,
  6
]
```

A throwing expression exits 2 with Go's `JS error: <cause>` prefix.

### Interact with elements

```bash
webb click "button#submit"       # Click element
webb input "#search" "query"     # Type into input field
webb clear "#search"             # Clear input field
webb file "#upload" photo.png    # Set file on a file input
webb file "#upload" -            # Set file from stdin
webb download "a.pdf-link"       # Download href/src target to file
webb download "a.pdf-link" -     # Download to stdout
webb select "#dropdown" "value"  # Select dropdown by value
webb submit "form#login"         # Submit a form
webb hover ".menu-item"          # Hover over element
webb focus "#email"              # Focus element
```

Each command echoes what it did:

```console
$ webb click "#submit"
Clicked

$ webb input "#search" "query"
Typed: query

$ webb clear "#search"
Cleared

$ webb select "#topic" support
Selected: support

$ webb hover ".menu-item"
Hovered

$ webb focus "#search"
Focused
```

`download` infers the filename from the href/src when no output file is given,
and `-` writes the payload bytes exactly as fetched (newline included when the
resource has one), so it can be piped:

```console
$ webb download "#link"
Saved testfile.txt (12 bytes)

$ webb download "#link" -
Hello World
```

`file` resolves relative paths against the current directory before handing the
path to Chrome; `-` drains stdin into a temporary `webb-upload-*` file.
`Set file: <arg>` echoes the argument you passed, including `-`.

### Wait for conditions

```bash
webb wait ".loaded"       # Wait for element to appear and be visible
webb waitload             # Wait for page load event
webb waitstable           # Wait for DOM to stop changing
webb waitidle             # Wait for browser idle callback
webb sleep 2.5            # Sleep for N seconds
```

```console
$ webb wait "#submit"
Element visible

$ webb waitload
Page loaded

$ webb waitstable
DOM stable

$ webb waitidle
Network idle
```

`waitidle` keeps upstream's `Network idle` line, but the behavior is Go's
`MustWaitIdle()`: a `window.requestIdleCallback` promise, not a network-idle
wait. `waitstable` runs `MustWaitStable()` (DOM stability plus request idle).

### Screenshots

```bash
webb screenshot                         # Save as screenshot.png
webb screenshot page.png                # Save to specific file
webb screenshot -w 1280 -h 720 out.png  # Set viewport width/height
webb screenshot-el ".chart" chart.png   # Screenshot specific element
```

Screenshots print the file they wrote; element screenshots print the byte count:

```console
$ webb screenshot
screenshot.png

$ webb screenshot -w 800 -h 600 demo.png
demo.png

$ webb screenshot-el "h1" chart.png
Saved chart.png (3398 bytes)
```

Without a filename, `screenshot` picks the next free `screenshot.png`,
`screenshot-2.png`, and so on.

### Manage tabs

```bash
webb pages                    # List all tabs (* marks active)
webb newpage https://...      # Open URL in new tab
webb page 1                   # Switch to tab by index
webb closepage 1              # Close tab by index
webb closepage                # Close active tab
```

```console
$ webb pages
  [0] Webb Demo - http://127.0.0.1:8765/
* [1] 127.0.0.1:8765/testfile.txt - http://127.0.0.1:8765/testfile.txt

$ webb page 0
Switched to [0] Webb Demo - http://127.0.0.1:8765/

$ webb closepage 1
Closed page 1
```

### Query elements

```bash
webb exists ".loading"    # Exit 0 if exists, exit 1 if not
webb count "li.item"      # Print number of matching elements
webb visible "#modal"     # Exit 0 if visible, exit 1 if not
webb assert 'document.title' 'Home'  # Exit 0 if equal, exit 1 if not
webb assert 'document.querySelector("h1") !== null'  # Exit 0 if truthy
```

```console
$ webb exists "#submit"
true

$ webb exists "#nope"
false

$ webb count "li.item"
3

$ webb visible "#hidden"
false
```

### Accessibility testing

```bash
webb ax-tree                           # Dump full accessibility tree
webb ax-tree --depth 3                 # Limit tree depth
webb ax-tree --json                    # Output as JSON

webb ax-find --role button             # Find all buttons
webb ax-find --name "Submit"           # Find by accessible name
webb ax-find --role link --name "Home" # Combine filters
webb ax-find --role button --json      # Output as JSON

webb ax-node "#submit-btn"             # Inspect element's a11y properties
webb ax-node "h1" --json               # Output as JSON
```

These commands use Chrome's
[Accessibility CDP domain](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/)
to expose what assistive technologies see. `ax-tree` uses `getFullAXTree`,
`ax-find` uses `queryAXTree`, and `ax-node` uses `getPartialAXTree`.

```console
$ webb ax-tree --depth 2
[RootWebArea] "Webb Demo" (focusable, focused)
  [heading] "Webb Demo" (level=1)
    [StaticText] "Webb Demo"
  [link] "Download" (focusable)
    [StaticText] "Download"
  [button] "Submit" (focusable)
    [StaticText] "Submit"
  ...

$ webb ax-find --role button
[button] "Submit" backendNodeId=17 (focusable)
[button] "Choose File" backendNodeId=32 (focusable)

$ webb ax-node "#submit"
role: button
name: Submit
invalid: false
focusable: true
```

```bash
# CI check: verify all buttons have accessible names
webb ax-find --role button --json | python3 -c "
import json, sys
buttons = json.load(sys.stdin)
unnamed = [b for b in buttons if not b.get('name', {}).get('value')]
if unnamed:
    print(f'FAIL: {len(unnamed)} button(s) missing accessible name')
    sys.exit(1)
print(f'PASS: all {len(buttons)} buttons have accessible names')
"
```

`ax-find` with no matches prints `No matching nodes` to stderr and exits 1, so
it doubles as a check.

### Directory-scoped sessions

By default, Webb stores state globally in `~/.rodney/`. You can instead create a
session scoped to the current directory with `--local`:

```bash
webb start --local          # State stored in ./.rodney/state.json
                            # Chrome data in ./.rodney/chrome-data/
webb open https://example.com   # Auto-detects local session
webb stop                       # Cleans up local session
```

```console
$ webb start --local
Chrome started (PID 45895)
Debug URL: ws://127.0.0.1:57882/devtools/browser/84b5fce9-...

$ ls -a .rodney
chrome-data  state.json
```

This is useful when you want isolated browser sessions per project — each
directory gets its own Chrome instance, cookies, and state.

**Auto-detection:** When neither `--local` nor `--global` is specified, Webb
checks for `./.rodney/state.json` in the current directory. If found, it uses
the local session; otherwise it falls back to the global `~/.rodney/` session.

```bash
# Force global even when a local session exists
webb --global open https://example.com

# Force local
webb --local status
```

The `--local` and `--global` flags can appear anywhere in the command:

```bash
webb --local start
webb start --local          # Same effect
webb open --global https://example.com
```

`RODNEY_HOME` wins over all of this: when it is set, both modes read and write
that directory (the same precedence as Go's `stateDir`).

Add `.rodney/` to your `.gitignore` to keep session state out of version
control.

### Shell scripting examples

```bash
# Wait for page to load and extract data
webb start
webb open https://example.com
webb waitstable
title=$(webb title)
echo "Page: $title"

# Conditional logic based on element presence
if webb exists ".error-message"; then
    webb text ".error-message"
fi

# Loop through pages
for url in page1 page2 page3; do
    webb open "https://example.com/$url"
    webb waitstable
    webb screenshot "${url}.png"
done

webb stop
```

## Exit codes

Webb uses distinct exit codes to separate check failures from errors:

| Exit code | Meaning |
|---|---|
| `0` | Success |
| `1` | Check failed — the command ran successfully but the condition/assertion was not met |
| `2` | Error — something went wrong (bad arguments, no browser session, timeout, etc.) |

This makes it easy to distinguish between "the assertion is false" and "the
command couldn't run" in scripts and CI pipelines.

```console
$ webb title
error: no browser session (run 'webb start' first)
$ echo $?
2

$ webb bogus
unknown command: bogus
webb - Chrome automation from the command line
...
$ echo $?
2
```

## Using Webb for checks

Several commands return **exit code 1** when a condition is not met, making them
useful as assertions in shell scripts and CI pipelines. All of these print their
result to stdout and exit cleanly — no error message is written to stderr.

### `exists` — check if an element exists in the DOM

```bash
webb exists "h1"
# Prints "true", exits 0

webb exists ".nonexistent"
# Prints "false", exits 1
```

### `visible` — check if an element is visible

```bash
webb visible "#modal"
# Prints "true" and exits 0 if the element exists and is visible

webb visible "#hidden-div"
# Prints "false" and exits 1 if the element is hidden or doesn't exist
```

### `ax-find` — check for accessibility nodes

```bash
webb ax-find --role button --name "Submit"
# Prints the matching node(s), exits 0

webb ax-find --role banner --name "Nonexistent"
# Prints "No matching nodes" to stderr, exits 1
```

### `assert` — assert a JavaScript expression

With one argument, checks that the expression is truthy. With two arguments,
checks that the expression's value equals the expected string. Use `--message` /
`-m` to set a custom failure message.

```bash
# Truthy mode — check that expression evaluates to a truthy value
webb assert 'document.querySelector(".logged-in") !== null'
# Prints "pass", exits 0

webb assert 'document.querySelector(".nonexistent")'
# Prints "fail: got null", exits 1

# Equality mode — check that expression result matches expected value
webb assert 'document.title' 'Dashboard'
# Prints "pass" if title is "Dashboard", exits 0

webb assert 'document.querySelectorAll(".item").length' '3'
# Prints "pass" if there are exactly 3 items, exits 0

webb assert 'document.title' 'Wrong Title'
# Prints 'fail: got "Dashboard", expected "Wrong Title"', exits 1
```

```console
$ webb assert 'document.title' 'Webb Demo'
pass

$ webb assert 'document.title' 'Wrong'
fail: got "Webb Demo", expected "Wrong"
$ echo $?
1
```

The expression is evaluated the same way as `webb js` — the result is converted
to its string representation before comparison. This means
`webb assert 'document.title' 'Dashboard'` compares the unquoted string, and
`webb assert '1 + 2' '3'` compares the number as a string.

Use `--message` (or `-m`) to add a human-readable description to the failure
output:

```bash
webb assert 'document.querySelector(".logged-in")' -m "User should be logged in"
# On failure: "fail: User should be logged in (got null)"

webb assert 'document.title' 'Dashboard' --message "Wrong page loaded"
# On failure: 'fail: Wrong page loaded (got "Home", expected "Dashboard")'
```

### Combining checks in a shell script

You can chain these together in a single script to run multiple assertions.
Because check failures use exit code 1 while real errors use exit code 2, you
can use `set -e` to abort on errors while handling check failures explicitly:

```bash
#!/bin/bash
set -euo pipefail

FAIL=0

check() {
    if ! "$@"; then
        echo "FAIL: $*"
        FAIL=1
    fi
}

webb start
webb open "https://example.com"
webb waitstable

# Assert elements exist
check webb exists "h1"
check webb exists "nav"
check webb exists "footer"

# Assert key elements are visible
check webb visible "h1"
check webb visible "#main-content"

# Assert JS expressions
check webb assert 'document.title' 'Example Domain'
check webb assert 'document.querySelectorAll("p").length' '2'
check webb assert 'document.querySelector("h1") !== null'

# Assert accessibility requirements
check webb ax-find --role navigation
check webb ax-find --role heading --name "Example Domain"

webb stop

if [ "$FAIL" -ne 0 ]; then
    echo "Some checks failed"
    exit 1
fi
echo "All checks passed"
```

This pattern is useful in CI — run Webb as a post-deploy check, an accessibility
audit, or a smoke test against a staging environment. Because exit code 2
signals an actual error (e.g. Chrome didn't start), `set -e` will abort the
script immediately if something is broken rather than reporting a misleading
test failure.

## Configuration

| Environment Variable | Default | Description |
|---|---|---|
| `RODNEY_HOME` | `~/.rodney` | Data directory for state and Chrome profile (overrides `--local`/`--global`) |
| `ROD_CHROME_BIN` | system Chrome | Path to Chrome/Chromium binary |
| `ROD_TIMEOUT` | `30` | Default timeout in seconds for element queries |
| `HTTPS_PROXY` / `HTTP_PROXY` | (none) | Authenticated proxy auto-detected on start |

Global state is stored in `~/.rodney/state.json` with Chrome user data in
`~/.rodney/chrome-data/`. When using `--local`, state is stored in
`./.rodney/state.json` and `./.rodney/chrome-data/` in the current directory
instead. Set `RODNEY_HOME` to override both.

## Proxy support

In environments with authenticated HTTP proxies (e.g.,
`HTTPS_PROXY=http://user:pass@host:port`), `webb start` automatically:

1. Detects the proxy credentials from environment variables
2. Launches a local forwarding proxy that injects `Proxy-Authorization` headers
   into CONNECT requests
3. Configures Chrome to use the local proxy

This is necessary because Chrome cannot natively authenticate to proxies during
HTTPS tunnel (CONNECT) establishment. The local proxy runs as a background
process and is automatically cleaned up by `webb stop`.

Both plain HTTP forwarding and HTTPS `CONNECT` tunneling work: Go hijacks the
connection with `http.Hijacker`, and the Crystal port serves `_proxy` on a raw
`TCPServer` so it can hand the socket to the upstream tunnel. Credentials come
from `HTTPS_PROXY` first, then `https_proxy`, `HTTP_PROXY`, and `http_proxy`.

## Commands reference

| Command | Arguments | Description |
|---|---|---|
| `start` | `[--show] [--insecure\|-k]` | Launch Chrome (headless by default, `--show` for visible) |
| `connect` | `<host:port>` | Connect to existing Chrome on remote debug port |
| `stop` | | Shut down Chrome |
| `status` | | Show browser status |
| `open` | `<url>` | Navigate to URL |
| `back` | | Go back in history |
| `forward` | | Go forward in history |
| `reload` | `[--hard]` | Reload page (`--hard` bypasses cache) |
| `clear-cache` | | Clear the browser cache |
| `url` | | Print current URL |
| `title` | | Print page title |
| `html` | `[selector]` | Print HTML (page or element) |
| `text` | `<selector>` | Print element text content |
| `attr` | `<selector> <name>` | Print attribute value |
| `pdf` | `[file]` | Save page as PDF (default `page.pdf`) |
| `js` | `<expression>` | Evaluate JavaScript |
| `click` | `<selector>` | Click element |
| `input` | `<selector> <text>` | Type into input |
| `clear` | `<selector>` | Clear input |
| `file` | `<selector> <path\|->` | Set file on a file input (`-` for stdin) |
| `download` | `<selector> [file\|-]` | Download href/src target (`-` for stdout) |
| `select` | `<selector> <value>` | Select dropdown value |
| `submit` | `<selector>` | Submit form |
| `hover` | `<selector>` | Hover over element |
| `focus` | `<selector>` | Focus element |
| `wait` | `<selector>` | Wait for element to appear |
| `waitload` | | Wait for page load |
| `waitstable` | | Wait for DOM stability |
| `waitidle` | | Wait for browser idle callback |
| `sleep` | `<seconds>` | Sleep N seconds |
| `screenshot` | `[-w N] [-h N] [file]` | Page screenshot (optional viewport size) |
| `screenshot-el` | `<selector> [file]` | Element screenshot |
| `pages` | | List tabs |
| `page` | `<index>` | Switch tab |
| `newpage` | `[url]` | Open new tab |
| `closepage` | `[index]` | Close tab |
| `exists` | `<selector>` | Check element exists (exit 1 if not) |
| `count` | `<selector>` | Count matching elements |
| `visible` | `<selector>` | Check element visible (exit 1 if not) |
| `assert` | `<expr> [expected] [-m msg]` | Assert JS expression is truthy or equals expected (exit 1 if not) |
| `ax-tree` | `[--depth N] [--json]` | Dump accessibility tree |
| `ax-find` | `[--name N] [--role R] [--json]` | Find accessible nodes |
| `ax-node` | `<selector> [--json]` | Show element accessibility info |

`webb help` prints this reference and exits 0; `webb` with no arguments prints
it and exits 2; an unknown command exits 2 and prints `unknown command: <cmd>`
first.

### Global flags

| Flag | Description |
|---|---|
| `--local` | Use directory-scoped session (`./.rodney/`) |
| `--global` | Use global session (`~/.rodney/`) |
| `--version` | Print version and exit |
| `--help`, `-h`, `help` | Show help message |

## How it works

The tool uses a Crystal shard ([rod](https://github.com/dsisnero/rod)) which
communicates with Chrome via the DevTools Protocol (CDP) over WebSocket. Key
implementation details:

- **`start`** uses rod's launcher with `leakless(false)` (Go's
  `Leakless(false)`) so Chrome survives after the CLI exits, saving the debug
  URL and PID
- **Proxy auth** is handled via a local forwarding proxy that bridges Chrome to
  authenticated upstream proxies (raw `TCPServer` for CONNECT)
- **State persistence** via a JSON file containing the WebSocket debug URL and
  Chrome PID
- **Each command** creates a new rod `Browser` connection to the same Chrome
  instance, executes the operation, and disconnects
- **Element queries** use rod's built-in auto-wait with a configurable timeout
  (default 30s, `ROD_TIMEOUT`)
- **JS evaluation** wraps user expressions in arrow functions as required by
  rod's `Eval`
- **Accessibility commands** call CDP's Accessibility domain directly via rod's
  `cdp` types (`getFullAXTree`, `queryAXTree`, `getPartialAXTree`)
- **OS failures** in `file`/`pdf`/`download`/`screenshot` print Go's
  `*PathError` text (`stat <path>: no such file or directory`,
  `open <path>: ...`)
- **SIGPIPE is ignored** like upstream's `init()`, so `webb ... | head` does not
  die on a closed stdout

## Differences from Rodney

The port keeps upstream's command names, flags, output, exit codes, and error
text. The documented differences are:

| Difference | Detail |
|---|---|
| Binary name | `webb` instead of `rodney`; usage/error lines and the upload temp prefix use `webb` |
| `start --show` | Upstream advertises `--show` but rejects it as an unknown flag; Webb accepts it |
| Short aliases | `axtree`, `axfind`, and `axnode` work as unadvertised aliases; the help text uses the hyphenated names |
| Upload paths | `webb file` resolves relative paths with `File.expand_path`, so a relative path works from any cwd; Go forwards the argument verbatim |
| Closed stdout | A broken stdout exits 0 without a stack trace; Go finishes the command and keeps its own status |
| Proxy helper | The detached `_proxy` helper runs without `Setsid`; it still outlives `start`, but Ctrl-C during `start` reaches it too |
| Write causes | Wrapped `File.write` failures print Go's `open <path>: <cause>` text through `Webb.go_path_error` |

Everything else is a port bug rather than a design choice — see
[docs/coding-guidelines.md](docs/coding-guidelines.md).

## Development

```bash
make install        # shards install
make update         # shards update
make format         # crystal tool format --check
make lint           # ameba --fix, then ameba
make test           # crystal spec (239 examples)
make build          # compile the CLI to bin/webb
make inventory      # tree-sitter parity gates against vendor/rodney
make parity-verify  # verify the installed parity skill + discovery backend
make docs-lint      # rumdl check README.md docs/ (skipped when rumdl is absent)
make clean          # remove temp/ contents and AppleDouble sidecars
```

## Contributing

1. Fork it (<https://github.com/dsisnero/webb/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT. See the `LICENSE` file for details. The original
[Rodney](https://github.com/simonw/rodney) project is Apache 2.0.
