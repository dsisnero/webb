# Agent Instructions

This is a port of Go https://github.com/simonw/rodney.git to
Crystal language. Since it is a port, all logic must match the Go implementation
only differening in Crystal language idioms and libs. If you have
a question, the go code is the source of truth. We want to port all go code and
go tests. The Go src is available at ./vendor/

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get
started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Issue Tracking Workflow

**DO NOT use internal todo list or task list tools** - Use beads for all issue
tracking and work management:

1. **Strategic, multi-session work**: Track in beads using `bd create`
2. **Dependencies and blockers**: Use `bd dep add` to link issues
3. **Session planning**: Use `bd ready` to find unblocked work
4. **Progress tracking**: Use `bd update <id> --status in_progress` when
   starting, `bd close <id>` when complete

**When creating multiple tasks**: Use parallel subagents for efficiency with
`bd create` commands.

**Example workflow**:

```bash
# Create issues for test porting
bd create --title="Port [module] tests from Go to Crystal spec" --type=task --priority=2
bd create --title="Port [module] tests from Go to Crystal spec" --type=task --priority=2
bd create --title="Port [module] tests from Go to Crystal spec" --type=task --priority=2

# Claim work
bd update beads-xxx --status=in_progress

# Complete work
bd close beads-xxx beads-yyy beads-zzz
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT
complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs
   follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
   - **Crystal-specific quality gates**:

      ```bash
      crystal tool format --check
      ameba --fix
      ameba
      crystal spec
      ```

      Ensure no formatting issues remain, all ameba errors are fixed, and all
      tests pass before committing.
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:

   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

## Crystal Development Guidelines

This is a Crystal port of the Go code from `./vendor/`. Follow Crystal idioms and
best practices:

- Use Crystal's built-in formatter: `crystal tool format`
- Use ameba for linting: `ameba --fix` then `ameba` to verify
- Prefer Crystal's standard library over custom implementations
- Use Crystal's type system effectively (avoid unnecessary `as` casts)
- Follow Crystal naming conventions (snake_case for methods/variables, CamelCase
  for classes)
- Write specs for new functionality using Crystal's built-in spec framework

### Test Porting Guidelines

When porting Go tests to Crystal specs:

1. **Port test logic exactly** - Don't adjust test assertions or expected values
2. **Use Crystal idioms for structure** - Convert Go test tables to Crystal `it`
   blocks
3. **Mark missing functionality as pending** - Use `pending` for tests that
   can't run yet
4. **Follow Go test patterns** - Maintain the same test coverage and edge cases
5. **Verify against Go implementation** - Ensure Crystal behavior matches Go
   exactly

Example: If a Go test expects compressed data of specific size, replicate that
check in Crystal even if Crystal's compression produces slightly different
output.

## File System Guidelines

- Use `./temp` directory for temporary files created during testing or
  development
- Never commit temporary files to git (they are already in `.gitignore`)
- Clean up temporary files after use (the `make clean` rule removes `./temp`
  contents)

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Dolt-powered version control with native sync
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update <id> --claim --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task atomically**: `bd update <id> --claim`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Auto-Sync

bd automatically syncs via Dolt:

- Each write auto-commits to Dolt history
- Use `bd dolt push`/`bd dolt pull` for remote sync
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- END BEADS INTEGRATION -->
