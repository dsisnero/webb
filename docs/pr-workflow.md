# PR Workflow

## Before Submitting

Run all quality gates. All must pass with zero errors:

```bash
make format        # Crystal formatter check — must not modify any files
make lint          # Ameba lint — must report "No issues found"
make test          # Crystal specs — all must pass (239 examples)
make build         # Compile the CLI to bin/webb
make inventory     # Parity ledger gates — no stale or missing rows
make parity-verify # Installed parity skill + tree-sitter backend
make docs-lint     # rumdl check README.md docs/ (skipped when rumdl is absent)
```

`make inventory` and `make parity-verify` need the cross-language parity skill
and the chiasmus toolchain from `AGENTS.md`; both report
`PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter`. A `regex` backend counts as a
failed gate.

## PR Body Template

Each PR should include:

1. **Upstream reference**: The Go function(s) or test(s) this PR ports/affects
   (e.g., `vendor/rodney/main.go:1234-1290`)
2. **Parity evidence**: What behavior was verified against the Go
   implementation, and the red proof if a divergence was fixed
3. **Files changed**: Brief summary of each modified file
4. **Testing**: Which spec cases cover this change
5. **Divergences**: Any intentional difference, linked to `plans/parity.md`

Example:

```text
## Upstream reference
Ports command entry points from vendor/rodney/main.go:684-707 (cmdPDF).

## Files changed
- src/cli.cr: cmd_pdf now wraps generate/write failures with Go's fatals
- spec/cli_spec.cr: live PDF example plus an unwritable-path example

## Testing
2 new examples: `Saved cli-spec.pdf (<n> bytes)` with the file starting %PDF,
and `error: failed to write PDF: open <path>: no such file or directory`.

## Divergences
None. The write cause uses Webb.go_path_error, which reproduces Go's
*PathError text.
```

## Parity Inventory Update

Every feature closes its ledger rows in `plans/inventory/go_port_inventory.tsv`:

- Set `status` to `ported` for completed items
- Use `intentional_divergence` only with a matching entry in
  `plans/parity.md`'s **Intentional divergences** (and a spec that pins it)
- `partial` is reserved for a real gap; the current baseline has none
- Add `crystal_refs` with the implementation and spec symbols (the gate checks
  that each referenced file exists)
- Add `notes` with the Go line range, the observed contract, and the covering
  examples

Then refresh `plans/parity.md`'s **Where we are** block and tick or remove the
queue item. Use the helper scripts to regenerate and validate:

```bash
PORT_PARSER=tree-sitter ./scripts/generate_go_port_inventory.sh . \
  plans/inventory/go_port_inventory.tsv vendor/rodney go
make inventory                          # Report gaps
```

## Commit Message Convention

Follow `AGENTS.md`. Start with `port:` for behavior work and `docs:` for
plan/doc-only changes, then the upstream revision:

```text
port: <one-line feature name>

- what changed and why (the Go contract, line ranges)
- spec: red first (the failing observation), then green
- coverage: which examples pin it
- ledger: <rows> -> <status>
- plans: <where we are / next up>
- divergences: <any, linked to plans/parity.md>

Gates: make format pass; make lint pass; make test N examples, 0 failures;
make build; make inventory pass (83 curated / 83 source / 63 tests,
chiasmus-tree-sitter).

Upstream: simonw/rodney v0.4.0 (9e7ae93900bcb5316d02623706bc8861feec836f)
```

One feature per commit. A commit that closes two checklist items is two commits.

## Review Checklist

- [ ] All quality gates pass (`make format lint test build inventory`)
- [ ] Behavior matches Go implementation (tested manually or via spec)
- [ ] Red proof recorded for every behavior change
- [ ] No intentional behavior changes without a `plans/parity.md` entry and a
      spec
- [ ] New code follows coding guidelines in `docs/coding-guidelines.md`
- [ ] Parity inventory updated, `make inventory` clean
- [ ] Exit codes follow convention (0/1/2)
- [ ] No commented-out code or debug prints

## Continuous Integration

There is no workflow committed under `.github/` yet, so the gates above run
locally (and in whatever CI a fork wires up). `make test` needs a real Chrome
plus the exFAT-safe sidecar cleanup that the Makefile targets already perform;
`make inventory` additionally needs the parity skill installed. If you add CI,
run the same five targets in that order and fail the job when
`PARITY_DISCOVERY_BACKEND` is not `chiasmus-tree-sitter`.
