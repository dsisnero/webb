# Testing

## Running Tests

```bash
make test        # Runs crystal spec
crystal spec     # Direct invocation
```

Tests require Chrome/Chromium installed. Set `ROD_CHROME_BIN` to override the binary path.

## Spec Structure

Browser parity tests live in `spec/webb_spec.cr`. CLI process tests live in
`spec/cli_spec.cr`; the two files share `spec/spec_helper.cr`.

### Test Infrastructure

- **`AXSpecEnv`** class: Manages a shared headless Chrome browser and an `HTTP::Server`
  test fixture with routes: `/`, `/form`, `/upload`, `/download`, `/testfile.txt`, `/empty`
- Chrome is launched once via `before_all` and killed via `after_all`
- A global `WebbSpecSupport` module holds the singleton env
- **`CLISpecHarness`** (in `spec/cli_spec.cr`): builds `src/main.cr` into
  `temp/cli_spec/webb` once, then runs that binary with a scrubbed environment
  (`HOME` and `RODNEY_HOME` point at `temp/cli_spec/home`, the working directory
  is `temp/cli_spec/workdir`) and captures stdout, stderr, and exit status
  together. Use it for anything upstream's `main` or a `cmd*` function prints;
  it never touches the developer's real session.
- **Live-browser CLI specs** use `run_cli_live`, which points `RODNEY_HOME` at
  `temp/cli_spec/browser_home` instead. On first use the harness launches one
  headless Chrome (same flags as `AXSpecEnv`), serves a fixture page titled
  `CLI Fixture` from an in-process `HTTP::Server`, and writes a `state.json`
  holding the launcher's debug URL and PID. `after_all` kills the launcher and
  the server, so no Chrome outlives the suite.

```crystal
result = run_cli("bogus")
result.status.should eq(2)
result.stderr.should eq("unknown command: bogus\n")
result.stdout.should contain("webb - Chrome automation")

run_cli_live("open", CLISpecSupport.harness.fixture_url).stdout.should eq("CLI Fixture\n")
```

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
| CLI process contract (`spec/cli_spec.cr`) | ~270 | 11 | Usage, help, version, unknown command, scope-only, help text parity, exit statuses, live `open`/`title`/`url`, `waitstable` timing, and the no-session error |

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
