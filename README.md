# webb: Crystal port of Rodney

**This is a Crystal port of [Rodney](https://github.com/simonw/rodney)**, a CLI tool for Chrome automation from the command line.

The original Go source code is available as a git submodule in the `vendor/` directory (commit `9e7ae93900bcb5316d02623706bc8861feec836f`, tag v0.4.0).

## Overview

Rodney is a Go CLI tool that drives a persistent headless Chrome instance using the [rod](https://github.com/go-rod/rod) browser automation library. Each command connects to the same long-running Chrome process, making it easy to script multi-step browser interactions from shell scripts or interactive use.

This Crystal port aims to replicate the functionality of the original Go implementation using Crystal's native capabilities and appropriate Crystal shards.

## Installation

1. Install Crystal (>= 1.19.1) and Shards.
2. Clone this repository with submodules:

   ```bash
   git clone --recurse-submodules https://github.com/dsisnero/webb.git
   cd webb
   ```

3. Install dependencies:

   ```bash
   make install
   ```

4. Build the binary:

   ```bash
   make build
   ```

The executable will be placed in `bin/webb`.

## Usage

*(The following usage documentation is adapted from the original Rodney README. Commands may not yet be fully implemented in the Crystal port.)*

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

## Development

This is a work-in-progress Crystal port. To contribute to the port:

1. Run the formatter: `make format`
2. Run the linter: `make lint`
3. Run tests: `make test`

See `AGENTS.md` for detailed instructions on issue tracking and porting workflow.

## Contributing

1. Fork it (<https://github.com/dsisnero/webb/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

Apache 2.0 (same as the original Rodney project). See `LICENSE` file for details.