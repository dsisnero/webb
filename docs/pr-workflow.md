# PR Workflow

## Before Submitting

Run all quality gates. All must pass with zero errors:

```bash
make format    # Crystal formatter check — must not modify any files
make lint      # Ameba lint — must report "No issues found"
make test      # Crystal specs — all must pass
make inventory # Parity ledger gate — no stale or missing rows
```

## PR Body Template

Each PR should include:

1. **Upstream reference**: The Go function(s) or test(s) this PR ports/affects
   (e.g., `vendor/rodney/main.go:L1234-L1290`)
2. **Parity evidence**: What behavior was verified against the Go implementation
3. **Files changed**: Brief summary of each modified file
4. **Testing**: Which spec cases cover this change

Example:

```
## Upstream reference
Ports `connectBrowser` and `getPage` from vendor/rodney/main.go:L400-L480.

## Files changed
- src/webb.cr: Added `State` struct with JSON serialization
- spec/webb_spec.cr: Added `State` round-trip and scope mode tests

## Testing
7 new spec cases in webb_spec.cr covering struct serialization,
load/save cycle, and scope mode resolution.
```

## Parity Inventory Update

When porting Go code, update `plans/inventory/go_port_inventory.tsv`:
- Set `status` to `ported` for completed items
- Set `status` to `partial` if blocked by rod shard limitations
- Add `crystal_refs` with file:line pointers
- Add `notes` for any blockers or deviations

Use the helper scripts to regenerate and validate:

```bash
PORT_PARSER=tree-sitter ./scripts/generate_go_port_inventory.sh . \
  plans/inventory/go_port_inventory.tsv vendor/rodney go
make inventory                          # Report gaps
```

## Commit Message Convention

```
<action>: <brief description>

Ports <Go functions/tests> from vendor/rodney.

- bullet points for specific changes
- reference upstream commit if relevant
```

## Review Checklist

- [ ] All quality gates pass (`make format lint test`)
- [ ] Behavior matches Go implementation (tested manually or via spec)
- [ ] No intentional behavior changes without documentation
- [ ] New code follows coding guidelines in `docs/coding-guidelines.md`
- [ ] Parity inventory updated in `plans/inventory/`
- [ ] Exit codes follow convention (0/1/2)
- [ ] No commented-out code or debug prints

## CI Workflow

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs:
1. `make format` — rejects unformatted code
2. `make lint` — rejects lint violations
3. `make test` — runs full spec suite with live Chrome

All three must be green for merge.
