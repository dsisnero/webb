# Coding Guidelines

## Upstream Parity First

All Crystal code must match the Go behavior in `vendor/rodney/main.go`. The Go
source is the **source of truth** — Crystal is just the translation layer.

### What to Preserve Exactly

- Function behavior (same inputs → same outputs)
- CLI argument parsing and flags
- Exit codes (0 = success, 1 = check failed, 2 = error)
- Output formatting (whitespace, quoting, JSON structure)
- Error text, including the prefixes Go's `fatal` calls use
- State file schema (JSON keys must match Go's struct tags)

### Where Crystal Differs

- **Naming**: `snake_case` methods/variables, `CamelCase` types
- **Types**: Crystal's nilable types (`String?`), enums, `JSON::Serializable`
- **Error handling**: Crystal exceptions/optionals vs Go's `(value, error)`
  tuples
- **Concurrency**: Crystal fibers vs Go goroutines (used sparingly; most code is
  synchronous)

### Divergence Rule

Port the Go behavior as-is. Diverge only when one of these holds:

1. Crystal cannot express it (e.g. `HTTP::Server` cannot hand a connection back
   after `CONNECT`, so `_proxy` runs on a raw `TCPServer` to tunnel the way Go's
   `http.Hijacker` does; the observable behavior still matches);
2. the Crystal stdlib does the same thing with the same observable result (e.g.
   `URI.parse` for URL handling);
3. the Go algorithm needs primitives Crystal lacks, in which case translate Go's
   own algorithm rather than inventing a new one (e.g. `net.SplitHostPort` in
   `valid_host_port?`).

Everything else is a bug in the port, not a design choice. Classes vs structs,
macros, and generics are implementation tools, not permission to change
behavior: `State` stays a struct with Go's exact JSON keys, and the CLI stays an
explicit `case` dispatch rather than a macro table. Any remaining divergence
needs a plan note **and** a spec that pins the Crystal behavior, so it is
visible instead of accidental. The open list lives in `plans/parity.md`
(**Intentional divergences**) and the README's **Differences from Rodney**.

Current intentional divergences:

| Area | Why | Pinned by |
|---|---|---|
| `webb file` upload path | `File.expand_path` makes relative paths work; Go forwards the argument verbatim | `spec/cli_spec.cr` "sets a file input and echoes the argument" |
| Closed stdout | Crystal raises `IO::Error` on EPIPE; `src/main.cr` exits 0 instead of finishing the command | `spec/cli_spec.cr` "finishes normally when stdout is closed…" |
| Detached `_proxy` helper | `Process.new` has no `setsid`; the helper still outlives `start` | `spec/cli_spec.cr` "starts the auth proxy helper and stops it with the session" |
| `--show`, `axtree`/`axfind`/`axnode` | Upstream advertises `--show` but rejects it; the aliases are unadvertised conveniences | `spec/cli_spec.cr` |

## Code Organization

| Concern | Location | Pattern |
|---|---|---|
| Entry point | `src/main.cr` | `require "./cli"` plus the SIGPIPE-tolerant `CLI.run` wrapper |
| Core logic (state, formatting, accessibility) | `src/webb.cr` | Module methods (`def self.method_name`) |
| CLI commands (arg parsing, user interaction) | `src/cli.cr` | Class methods on `Webb::CLI` |

**Rationale**: The split (`webb.cr` / `cli.cr`) separates pure logic from CLI
glue, making it easier to test formatting, assertions, and accessibility
functions without needing to parse ARGV. `Webb.cmd_assert` lives in `webb.cr`
for the same reason: the whole assert evaluation is testable without the process
boundary.

## Naming Conventions

- Crystal `def` methods: `snake_case` (`cmd_ax_tree`, `resolve_state_dir`)
- Module name: `Webb` (CamelCase)
- Class name: `Webb::CLI` (namespaced)
- Struct name: `Webb::State` (namespaced)
- Enum: `Webb::ScopeMode` with members `Auto`, `Local`, `Global`
- Constants: `VERSION`, `DEFAULT_TIMEOUT` (SCREAMING_SNAKE_CASE)
- Private methods: `private def walk_ax_tree` (explicit `private` keyword)
- Parity helpers keep upstream's intent in the name (`go_path_error` mirrors
  Go's `*PathError`, `load_state?` mirrors Go's `(state, error)` return)

## Exit Code Convention

```crystal
# Success — command completed
exit 0

# Check failed — assertion/element check was false
exit 1

# Error — bad args, no browser, timeout, etc.
Webb.fatal("message")  # exits 2, prints to stderr
```

Commands that check conditions (`exists`, `visible`, `assert`, `ax-find` with no
results) use exit code 1 to signal "condition not met" without indicating an
error.

## Formatting and Linting

```bash
make format    # crystal tool format --check (rejects unformatted code)
make lint      # ameba --fix (auto-fix) then ameba (verify clean)
```

Run both before committing. The gates are
`make format && make lint && make test && make build && make inventory`.

## When to Use `fatal` vs `exit`

```crystal
# Use fatal for errors that should print to stderr with exit code 2
Webb.fatal("no browser session (run 'webb start' first)")

# Use exit for normal termination or check failures
exit 0   # success
exit 1   # check failure (exists/visible/assert returned false)
```

`Webb.fatal` mirrors Go's writer: it prints `error: <message>` to stderr,
ignores a closed stderr (so a broken pipe cannot change the exit code), and
exits 2.

## OS Errors: Use `go_path_error`

Go wraps `os.Stat`/`os.WriteFile`/`os.MkdirAll` failures in `*PathError`, whose
text is `<op> <path>: <cause>` with a lowercase cause. Crystal's `File` errors
use different phrasing
(`Error opening file with mode 'w': '<path>': Permission denied`). Any fatal
that wraps a file-system failure must go through `Webb.go_path_error`:

```crystal
begin
  File.write(path, data)
rescue ex
  Webb.fatal("failed to write PDF: #{Webb.go_path_error("open", path, ex)}")
end
```

`save_state` raises the formatted message itself so every caller's
`failed to save state: <cause>` matches upstream. Directories created by
`Dir.mkdir_p` use `"mkdir"`; writes use `"open"` (Go's `os.WriteFile` op for the
create step).

## Mapping Go's `Must*` Wrappers

Go's `MustX()` panics on error; Crystal's rod shard raises instead. Match the
*primitive*, not the convenience name, and check the shard's actual semantics:

```crystal
# Go: page.MustWaitIdle() = WaitIdle(time.Minute)  → requestIdleCallback
page.wait_idle(1.minute)

# NOT wait_request_idle, which waits for the network and is a different contract
```

When a `Must*` fails, the exception escapes like Go's panic (no extra `fatal`),
unless upstream wraps the call itself.

## Crystal-Specific Patterns

### JSON Serialization

Use Crystal's `JSON::Serializable` with explicit key mapping to match Go's JSON
tags:

```crystal
struct State
  include JSON::Serializable

  @[JSON::Field(key: "debug_url")]
  property debug_url : String = ""
  # ...
end
```

### Nilable Types

Use `nil` instead of Go's zero-value + boolean check pattern. The `?`-suffixed
helpers exist precisely to mirror Go's error returns at call sites:

```crystal
# Go: info, _ := page.Info(); if info != nil { ... }
if info = Webb.page_info?(page)
  puts info.title
end

# Go: s, err := loadState(); if err != nil { ... }
state = Webb.load_state?  # nil for missing or corrupt
```

### Error Handling

Prefer Crystal exceptions for truly exceptional cases, and `fatal` for anything
upstream treats as a user-facing error:

```crystal
# User-facing error — same text and exit code as Go
Webb.fatal("element not found: #{ex.message}")

# Programmer/structural error — let the exception escape
raise "expected a page"
```
