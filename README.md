# webb: Chrome automation from the command line (Crystal)

A Crystal port of [Rodney](https://github.com/simonw/rodney), a CLI tool that drives a persistent headless Chrome instance using the [rod](https://github.com/nicoretti/rod) Crystal shard. Each command connects to the same long-running Chrome process, making it easy to script multi-step browser interactions from shell scripts or interactive use.

## Architecture

```
webb start          →  launches Chrome (headless, persists after CLI exits)
                       saves WebSocket debug URL to ~/.rodney/state.json

webb connect H:P    →  connects to an existing Chrome on a remote debug port
                       saves WebSocket debug URL to ~/.rodney/state.json

webb open URL       →  connects to running Chrome via WebSocket
                       navigates the active tab, disconnects

webb js EXPR        →  connects, evaluates JS, prints result, disconnects

webb stop           →  connects and shuts down Chrome, cleans up state
```

Each CLI invocation is a short-lived process. Chrome runs independently and tabs persist between commands.

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

   Or use `make build` for the standard build process.

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

### Extract information

```bash
webb url                    # Print current URL
webb title                  # Print page title
webb text "h1"              # Print text content of element
webb html "div.content"     # Print outer HTML of element
webb html                   # Print full page HTML
webb attr "a#link" href     # Print attribute value
webb pdf output.pdf         # Save page as PDF
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

### Wait for conditions

```bash
webb wait ".loaded"       # Wait for element to appear and be visible
webb waitload             # Wait for page load event
webb waitstable           # Wait for DOM to stop changing
webb waitidle             # Wait for network to be idle
webb sleep 2.5            # Sleep for N seconds
```

### Screenshots

```bash
webb screenshot                         # Save as screenshot.png
webb screenshot page.png                # Save to specific file
webb screenshot -w 1280 -h 720 out.png  # Set viewport width/height
webb screenshot-el ".chart" chart.png   # Screenshot specific element
```

### Manage tabs

```bash
webb pages                    # List all tabs (* marks active)
webb newpage https://...      # Open URL in new tab
webb page 1                   # Switch to tab by index
webb closepage 1              # Close tab by index
webb closepage                # Close active tab
```

### Query elements

```bash
webb exists ".loading"    # Exit 0 if exists, exit 1 if not
webb count "li.item"      # Print number of matching elements
webb visible "#modal"     # Exit 0 if visible, exit 1 if not
webb assert 'document.title' 'Home'  # Exit 0 if equal, exit 1 if not
webb assert 'document.querySelector("h1") !== null'  # Exit 0 if truthy
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

These commands use Chrome's [Accessibility CDP domain](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/) to expose what assistive technologies see.

## Exit codes

Webb uses distinct exit codes to separate check failures from errors:

| Exit code | Meaning |
|---|---|
| `0` | Success |
| `1` | Check failed — the command ran successfully but the condition/assertion was not met |
| `2` | Error — something went wrong (bad arguments, no browser session, timeout, etc.) |

This makes it easy to distinguish between "the assertion is false" and "the command couldn't run" in scripts and CI pipelines.

## Using Webb for checks

Several commands return **exit code 1** when a condition is not met, making them useful as assertions in shell scripts and CI pipelines.

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

### `assert` — assert a JavaScript expression

With one argument, checks that the expression is truthy. With two arguments, checks that the expression's value equals the expected string. Use `--message` / `-m` to set a custom failure message.

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

Use `--message` (or `-m`) to add a human-readable description to the failure output:

```bash
webb assert 'document.querySelector(".logged-in")' -m "User should be logged in"
# On failure: "fail: User should be logged in (got null)"

webb assert 'document.title' 'Dashboard' --message "Wrong page loaded"
# On failure: 'fail: Wrong page loaded (got "Home", expected "Dashboard")'
```

### Directory-scoped sessions

By default, Webb stores state globally in `~/.rodney/`. You can instead create a session scoped to the current directory with `--local`:

```bash
webb start --local          # State stored in ./.rodney/state.json
                            # Chrome data in ./.rodney/chrome-data/
webb open https://example.com   # Auto-detects local session
webb stop                       # Cleans up local session
```

This is useful when you want isolated browser sessions per project — each directory gets its own Chrome instance, cookies, and state.

**Auto-detection:** When neither `--local` nor `--global` is specified, Webb checks for `./.rodney/state.json` in the current directory. If found, it uses the local session; otherwise it falls back to the global `~/.rodney/` session.

```bash
# Force global even when a local session exists
webb --global open https://example.com

# Force local (errors if no local session)
webb --local status
```

Add `.rodney/` to your `.gitignore` to keep session state out of version control.

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

### Combining checks in a shell script

You can chain checks together in a single script. Because check failures use exit code 1 while real errors use exit code 2, you can use `set -e` to abort on errors while handling check failures explicitly:

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

check webb exists "h1"
check webb visible "#main-content"
check webb assert 'document.title' 'Example Domain'
check webb ax-find --role heading --name "Example Domain"

webb stop

if [ "$FAIL" -ne 0 ]; then
    echo "Some checks failed"
    exit 1
fi
echo "All checks passed"
```

## Configuration

| Environment Variable | Default | Description |
|---|---|---|
| `RODNEY_HOME` | `~/.rodney` | Data directory for state and Chrome profile |
| `ROD_CHROME_BIN` | (system Chrome) | Path to Chrome/Chromium binary |
| `ROD_TIMEOUT` | `30` | Default timeout in seconds for element queries |
| `HTTPS_PROXY` / `HTTP_PROXY` | (none) | Authenticated proxy auto-detected on start |

Global state is stored in `~/.rodney/state.json` with Chrome user data in `~/.rodney/chrome-data/`. When using `--local`, state is stored in `./.rodney/state.json` and `./.rodney/chrome-data/` in the current directory instead. Set `RODNEY_HOME` to override the default global directory.

## Proxy support

In environments with authenticated HTTP proxies (e.g., `HTTPS_PROXY=http://user:pass@host:port`), `webb start` automatically:

1. Detects the proxy credentials from environment variables
2. Launches a local forwarding proxy that injects `Proxy-Authorization` headers into CONNECT requests
3. Configures Chrome to use the local proxy

The local proxy runs as a background process and is automatically cleaned up by `webb stop`.

**Note:** HTTP CONNECT tunneling is not supported in this Crystal port due to limitations in Crystal's HTTP::Server. HTTP proxy requests work, but HTTPS traffic through authenticated proxies requires the Go version.

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
| `pdf` | `[file]` | Save page as PDF |
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
| `waitidle` | | Wait for network idle |
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

### Global flags

| Flag | Description |
|---|---|
| `--local` | Use directory-scoped session (`./.rodney/`) |
| `--global` | Use global session (`~/.rodney/`) |
| `--version` | Print version and exit |
| `--help`, `-h`, `help` | Show help message |

## How it works

The tool uses a Crystal shard ([rod](https://github.com/nicoretti/rod)) which communicates with Chrome via the DevTools Protocol (CDP) over WebSocket. Key implementation details:

- **`start`** uses rod's launcher to start Chrome, returning a WebSocket debug URL
- **Proxy auth** handled via a local forwarding proxy that bridges Chrome to authenticated upstream proxies
- **State persistence** via a JSON file containing the WebSocket debug URL and Chrome PID
- **Each command** creates a new rod Browser connection to the same Chrome instance, executes the operation, and disconnects
- **Element queries** use rod's built-in auto-wait with a configurable timeout (default 30s, configurable via `ROD_TIMEOUT`)
- **JS evaluation** wraps user expressions in arrow functions as required by rod's eval
- **Accessibility commands** call CDP's Accessibility domain directly via rod

## Development

```bash
crystal tool format    # Format code
ameba                  # Lint
crystal spec           # Run tests
```

## Contributing

1. Fork it (<https://github.com/dsisnero/webb/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

Apache 2.0 (same as the original [Rodney](https://github.com/simonw/rodney) project). See `LICENSE` file for details.
