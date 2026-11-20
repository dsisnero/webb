# Testing

## Running Tests

```bash
make test        # Runs crystal spec (239 examples)
crystal spec     # Direct invocation
```

One file or one example while iterating:

```bash
crystal spec spec/webb_spec.cr
crystal spec spec/cli_spec.cr
crystal spec spec/cli_spec.cr:1305     # single example by line
crystal spec spec/cli_spec.cr -e "download"
```

Tests require Chrome/Chromium installed. Set `ROD_CHROME_BIN` to override the
binary path; the CLI harness always passes it through so the suite stays offline
instead of downloading a ~130 MB snapshot through rod's launcher.

## Spec Structure

Browser parity tests live in `spec/webb_spec.cr` (100 examples). CLI process
tests live in `spec/cli_spec.cr` (139 examples); the two files share
`spec/spec_helper.cr`.

### Test Infrastructure

- **`AXSpecEnv`** class: Manages a shared headless Chrome browser and an
  `HTTP::Server` test fixture with routes: `/`, `/form`, `/upload`, `/download`,
  `/testfile.txt`, `/empty`
- Chrome is launched once via `before_all` and killed via `after_all`
- A global `WebbSpecSupport` module holds the singleton env; `navigate_to(path)`
  opens a page against it and specs close their own page in `ensure`
- **`CLISpecHarness`** (in `spec/cli_spec.cr`): builds `src/main.cr` into
  `temp/cli_spec/webb` once, then runs that binary with a scrubbed environment
  (`HOME` and `RODNEY_HOME` point at `temp/cli_spec/home`, the working directory
  is `temp/cli_spec/workdir`) and captures stdout, stderr, and exit status
  together. Use it for anything upstream's `main` or a `cmd*` function prints;
  it never touches the developer's real session. `run(..., input: "text")` feeds
  stdin for `file ... -`.
- **Live-browser CLI specs** use `run_cli_live`, which points `RODNEY_HOME` at
  `temp/cli_spec/browser_home` instead. On first use the harness launches one
  headless Chrome (same flags as `AXSpecEnv`), serves fixture pages from an
  in-process `HTTP::Server`, and writes a `state.json` holding the launcher's
  debug URL and PID. `reset_pages` closes every page through one long-lived
  control connection so a spec can start from zero pages; it never calls
  `Browser#close`, which shuts Chrome down. `after_all` kills the launcher and
  the server, so no Chrome outlives the suite.
  `state_home`/`raw_state_home`/`session_home` write a `state.json` (valid or
  arbitrary) for `stop`/`status`/`start` scenarios, and `owned_browser` launches
  a tracked throwaway Chrome whose PID can be checked after `stop`.
- **CLI fixture routes**: `/` (the shared fixture page with `#topic`,
  `#search-form`, `#file-input`/`#file-summary`, `#file-link`, `#missing-link`),
  `/slow` (a 2s response), `/slow-page` (polls `/slow` so `waitstable` must wait
  for in-flight requests), `/late-page` (keeps `#late` hidden for two seconds so
  `wait` must block), `/download/testfile.txt`, and a 404
  `/download/missing.txt` (a `download failed:` red). `spawn_cli` starts the
  binary without waiting (used by `_proxy` and the ROD_TIMEOUT examples) and
  accepts `env:` additions.

```crystal
result = run_cli("bogus")
result.status.should eq(2)
result.stderr.should eq("unknown command: bogus\n")
result.stdout.should contain("webb - Chrome automation")

run_cli_live("open", CLISpecSupport.harness.fixture_url).stdout.should eq("CLI Fixture\n")
```

### Test Categories

`spec/webb_spec.cr` — module behavior, mostly upstream parity:

| Describe | Examples | What's tested |
|---|---|---|
| `.extract_scope_args` | 5 | `--local`/`--global` flag parsing |
| `.resolve_state_dir` | 5 | State directory resolution logic |
| `.state_dir` | 2 | Default and `RODNEY_HOME` override |
| `.detect_proxy` | 8 | Env priority, empty values, missing user/password, portless host, IPv6, malformed |
| `.next_available_file` | 3 | `base`, `base-2`, `base-3`, empty extension, directory counts as taken |
| `.connect_browser` | 1 | Go's `failed to connect to browser (is it still running?)` wrapper |
| `.load_state?` | 3 | `nil` for missing/corrupt, full round-trip for valid |
| `.save_state` / `.remove_state` | 4 | Go-shaped `*PathError` on write failure, ignored removal errors |
| `.page_info` / `.format_page_list` | 6 | Info success/failure, list markers |
| `.ax_value_str` | 2 | JSON string unquoting, raw JSON passthrough |
| `.format_properties` | 2 | Boolean-only-true, unconditional `level=`, empty values |
| `.format_ax_node_list` / `.format_ax_node_detail` | 5 | One-line summaries, zero `backendNodeId`, detail fields |
| `.format_ax_tree` | 5 | Tree rendering (nodes, indent, ignored, depth, JSON) |
| `.query_ax_nodes` / `.get_ax_node` | 12 | AX query by role/name, combined filters, element AX info |
| `.assert browser parity` | 12 | JS assert truthy/equality across value types |
| `.parse_assert_args` / `.format_assert_fail` | 10 | Assert argument parsing and failure text |
| `.decode_data_url` / `.go_path_error` / `.mime_to_ext` | 6 | Data URLs, Go `*PathError` text, MIME mapping |
| `.infer_download_filename` | 2 | Filename extraction from URL and data URL |
| `.download` / `.file` browser parity | 5 | Fetch, `data:`, `img src`, single and multiple uploads |
| `--insecure with a self-signed certificate` | 2 | TLS errors ignored end to end |

`spec/cli_spec.cr` — the process contract:

| Describe | Examples | What's tested |
|---|---|---|
| `CLI process contract` | 22 | Usage/help/version, unknown command, scope-only, exit statuses, arg diagnostics, `connect` validation and failures, `stop` paths |
| `CLI auth proxy` | 3 | CONNECT tunneling, upstream 5xx, auth header injection |
| `CLI start` | 4 | Session creation, stale state, `--insecure`, proxy helper lifecycle |
| `CLI against a live browser` | 110 | Navigation, tabs, extraction, interaction, waits, screenshots, PDFs/downloads/uploads, AX commands, checks, state helpers, ROD_TIMEOUT cases, SIGPIPE |

### Test Pattern

Tests follow the Go test logic exactly. Each Crystal `it` block mirrors a Go
`t.Run` case:

```crystal
# Crystal (spec/webb_spec.cr)
it "matches TestAXFind_ByRole" do
  nodes = Webb.query_ax_nodes(page, name: "", role: "button")
  nodes.size.should be > 0
end
```

```go
// Go (vendor/rodney/main_test.go)
t.Run("byRole", func(t *testing.T) {
    nodes, err := queryAXNodes(page, "", "button")
    assert.NoError(t, err)
    assert.Greater(t, len(nodes), 0)
})
```

Where upstream has no test (many `cmd*` functions), write a **characterization**
spec that pins the Go contract from the source; start red where a real
divergence exists (`exit 1` where Go prints `error: ...` and exits 2, a message
that does not match, a wrong rod primitive) and only then change product code.

## Parity Manifests

Test coverage is tracked in `plans/inventory/go_test_parity.tsv`. Each row maps
a Go test function to its Crystal port status:

- **Column `status`**: `ported` (implemented and passing), `partial`
  (incomplete), or `intentional_divergence` (documented in `plans/parity.md`)
- **Column `crystal_refs`**: Crystal file/spec anchors (a file must exist; the
  gate fails when a referenced file is missing)
- **Column `notes`**: Evidence and any divergence

The first line of every manifest is a `# baseline=` comment naming the pinned
upstream release and the discovery parser. The ledger is a current-state
artifact: re-base it when the pin moves, never append across versions.

The suite has **no `pending` examples**: a behavior that cannot run yet is
either closed with a structural note in the ledger or blocked by a shard fix
first.

## Regenerating Parity Reports

The scripts in `scripts/` are thin forwarding wrappers around the installed
cross-language parity skill (`PARITY_SKILL_DIR`, default
`~/.agents/skills/crystal_forge/skills/cross-language-crystal-parity`). Never
copy the skill's Ruby helpers into this repo.

```bash
# Regeneration refuses to overwrite a curated manifest unless forced; prefer the
# gate. For a reviewed reset of the test manifest only:
PORT_PARSER=tree-sitter PORT_FORCE_OVERWRITE=1 \
  ./scripts/generate_go_test_parity_manifest.sh \
  . plans/inventory/go_test_parity.tsv vendor/rodney go

make inventory     # Drift/gap gate across all three manifests
make parity-verify # Verify the installed skill + discovery backend
```
