# Testing

## Running Tests

```bash
make test        # Runs crystal spec
crystal spec     # Direct invocation
```

Tests require Chrome/Chromium installed. Set `ROD_CHROME_BIN` to override the binary path.

## Spec Structure

All tests live in `spec/webb_spec.cr` (~853 lines). No separate per-module spec files.

### Test Infrastructure

- **`AXSpecEnv`** class: Manages a shared headless Chrome browser and an `HTTP::Server`
  test fixture with routes: `/`, `/form`, `/upload`, `/download`, `/testfile.txt`, `/empty`
- Chrome is launched once via `before_all` and killed via `after_all`
- A global `WebbSpecSupport` module holds the singleton env

### Test Categories

| Category | Lines | Tests | What's tested |
|---|---|---|---|
| `.extract_scope_args` | ~30 | 5 | `--local`/`--global` flag parsing |
| `.resolve_state_dir` | ~40 | 5 | State directory resolution logic |
| `.state_dir` | ~10 | 2 | Default and `RODNEY_HOME` override |
| `.format_ax_tree` | ~100 | 5 | AX tree rendering (nodes, indent, ignored, depth, JSON) |
| `.query_ax_nodes` | ~80 | 6 | AX query by role, name, combined, no-results, form page |
| `.get_ax_node` | ~70 | 6 | Element AX info by selector, disabled, input label, heading, JSON, not found |
| `.assert` (parity) | ~140 | 11 | JS assert truthy/equality with various value types |
| `.parse_assert_args` | ~30 | 6 | Assert command argument parsing |
| `.format_assert_fail` | ~30 | 4 | Assert failure message formatting |
| `.decode_data_url` | ~30 | 3 | Data URL decoding (base64, URL-encoded, invalid) |
| `.mime_to_ext` | ~15 | 1 | MIME type → file extension mapping |
| `.infer_download_filename` | ~25 | 2 | Filename extraction from URL and data URL |
| `.download` (parity) | ~80 | 3 | Downloading link targets (fetch, data:, img src) |
| `.file` (parity) | ~60 | 2 | File input setting (single, multiple) |

### Test Pattern

Tests follow the Go test logic exactly. Each Crystal `it` block mirrors a Go `t.Run` case:

```crystal
# Crystal (spec/webb_spec.cr)
it "extracts by role" do
  nodes = Webb.query_ax_nodes(@page, role: "heading")
  nodes.size.should be > 0
end
```

```go
// Go (vendor/rodney/main_test.go)
t.Run("byRole", func(t *testing.T) {
    nodes, err := queryAXNodes(page, "", "heading")
    assert.NoError(t, err)
    assert.Greater(t, len(nodes), 0)
})
```

## Parity Manifests

Test coverage is tracked in `plans/inventory/go_test_parity.tsv`. Each row maps a Go test
function to its Crystal port status:

- **Column `status`**: `ported` (implemented and passing), `partial` (incomplete or
  browser-dependent), or empty (not yet ported)
- **Column `crystal_refs`**: Crystal file/spec anchors (a file must exist; the
  gate fails when a referenced file is missing)
- **Column `notes`**: Blockers (e.g., rod shard limitations)

The first line of every manifest is a `# baseline=` comment naming the pinned
upstream release and the discovery parser. The ledger is a current-state
artifact: re-base it when the pin moves, never append across versions.

## Marking Pending Tests

Tests that cannot run yet (blocked by rod shard issues) should be marked with
`pending` in the spec:

```crystal
pending "download with specified filename" do
  # Blocked by rod issue: Page.evaluate not returning response body
end
```

## Regenerating Parity Reports

The scripts in `scripts/` are thin forwarding wrappers around the installed
cross-language parity skill (`PARITY_SKILL_DIR`, default
`~/.agents/skills/crystal_forge/skills/cross-language-crystal-parity`). Never
copy the skill's Ruby helpers into this repo.

```bash
# Regeneration refuses to overwrite a curated manifest unless forced; prefer the
# gate. For a reviewed reset of the test manifest only:
PORT_PARSER=tree-sitter PORT_FORCE_OVERWRITE=1 \
  ./scripts/generate_go_test_parity_manifest.sh . plans/inventory/go_test_parity.tsv \
  vendor/rodney go

make inventory     # Drift/gap gate across all three manifests
make parity-verify # Verify the installed skill + discovery backend
```
