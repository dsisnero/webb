# Coding Guidelines

## Upstream Parity First

All Crystal code must match the Go behavior in `vendor/rodney/main.go`. The Go source is
the **source of truth** — Crystal is just the translation layer.

### What to Preserve Exactly
- Function behavior (same inputs → same outputs)
- CLI argument parsing and flags
- Exit codes (0 = success, 1 = check failed, 2 = error)
- Output formatting (whitespace, quoting, JSON structure)
- State file schema (JSON keys must match Go's struct tags)

### Where Crystal Differs
- **Naming**: `snake_case` methods/variables, `CamelCase` types
- **Types**: Crystal's nilable types (`String?`), enums, `JSON::Serializable`
- **Error handling**: Crystal exceptions/optionals vs Go's `(value, error)` tuples
- **Concurrency**: Crystal fibers vs Go goroutines (used sparingly; most code is
  synchronous)

### Divergence Rule

Port the Go behavior as-is. Diverge only when one of these holds:

1. Crystal cannot express it (e.g. `HTTP::Server` cannot hijack a socket, so
   HTTPS `CONNECT` proxying returns 501 — `shard_issues/rod.001.md`);
2. the Crystal stdlib does the same thing with the same observable result
   (e.g. `URI.parse` for URL handling);
3. the Go algorithm needs primitives Crystal lacks, in which case translate
   Go's own algorithm rather than inventing a new one (e.g. `net.SplitHostPort`
   in `valid_host_port?`).

Everything else is a bug in the port, not a design choice. Classes vs structs,
macros, and generics are implementation tools, not permission to change
behavior: `State` stays a struct with Go's exact JSON keys, and the CLI stays an
explicit `case` dispatch rather than a macro table. Any remaining divergence
needs a `shard_issues/` entry or a plan note **and** a spec that pins the
Crystal behavior, so it is visible instead of accidental.

## Code Organization

| Concern | Location | Pattern |
|---|---|---|
| Core logic (state, formatting, accessibility) | `src/webb.cr` | Module methods (`def self.method_name`) |
| CLI commands (arg parsing, user interaction) | `src/cli.cr` | Class methods on `Webb::CLI` |
| Entry point | `src/main.cr` | Single `require` + `CLI.run(ARGV)` |

**Rationale**: The split (`webb.cr` / `cli.cr`) separates pure logic from CLI glue,
making it easier to test formatting, assertions, and accessibility functions without
needing to parse ARGV.

## Naming Conventions

- Crystal `def` methods: `snake_case` (`cmd_ax_tree`, `resolve_state_dir`)
- Module name: `Webb` (CamelCase)
- Class name: `Webb::CLI` (namespaced)
- Struct name: `Webb::State` (namespaced)
- Enum: `Webb::ScopeMode` with members `Auto`, `Local`, `Global`
- Constants: `VERSION`, `DEFAULT_TIMEOUT` (SCREAMING_SNAKE_CASE)
- Private methods: `private def walk_ax_tree` (explicit `private` keyword)

## Exit Code Convention

```crystal
# Success — command completed
exit 0

# Check failed — assertion/element check was false
exit 1

# Error — bad args, no browser, timeout, etc.
Webb.fatal("message")  # exits 2, prints to stderr
```

Commands that check conditions (`exists`, `visible`, `assert`, `ax-find` with no results)
use exit code 1 to signal "condition not met" without indicating an error.

## Formatting and Linting

```bash
make format    # crystal tool format --check (rejects unformatted code)
make lint      # ameba --fix (auto-fix) then ameba (verify clean)
```

Run both before committing. The CI workflow runs `make format && make lint && make test`.

## When to Use `fatal` vs `exit`

```crystal
# Use fatal for errors that should print to stderr with exit code 2
Webb.fatal("no browser session found (run 'webb start' first)")

# Use exit for normal termination or check failures
exit 0   # success
exit 1   # check failure (exists/visible/assert returned false)
```

## Crystal-Specific Patterns

### JSON Serialization

Use Crystal's `JSON::Serializable` with explicit key mapping to match Go's JSON tags:

```crystal
struct State
  include JSON::Serializable

  @[JSON::Field(key: "debug_url")]
  property debug_url : String = ""
  # ...
end
```

### Nilable Types

Use `nil` instead of Go's zero-value + boolean check pattern:

```crystal
# Crystal — nil means "not present"
nodes = Webb.query_ax_nodes(page, name: name, role: role)
return if nodes.nil?  # ← No results

# Go — separate boolean
nodes, ok, err := queryAXNodes(page, name, role)
if !ok { return }
```

### Error Handling

Prefer Crystal exceptions for truly exceptional cases, return nil for "not found":

```crystal
# "Not found" is expected — return nil
def self.query_ax_nodes(page, ...) : Array(AXNodeSummary)?
  # ...
end

# Unexpected failure — raise
def self.load_state : State
  raise "Failed to parse state file" unless state
  state
end
```
