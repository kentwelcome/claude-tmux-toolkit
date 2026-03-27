# claude-tmux-toolkit

A collection of tmux productivity plugins for Claude Code.

## Project Structure

```
.claude-plugin/                       # Marketplace registry (marketplace.json)
plugins/nvim-sidebar/
  .claude-plugin/plugin.json          # Plugin metadata
  hooks/hooks.json                    # PostToolUse hook — triggers on Write|Edit
  scripts/nvim-open.sh                # Opens/reuses nvim in a tmux split pane
  scripts/diff-signs.lua              # Git diff gutter signs — sourced by nvim after each edit
plugins/rename-window/
  .claude-plugin/plugin.json          # Plugin metadata
  hooks/hooks.json                    # SessionStart hook
  scripts/tmux-rename.sh              # Renames tmux window to PascalCase folder name
```

## How the Hooks Work

**nvim-sidebar**: Claude Code calls Write or Edit → `hooks.json` triggers `nvim-open.sh`
1. `nvim-open.sh` reads JSON from stdin (`tool_input.file_path` or `tool_response.filePath`)
2. Opens or reuses a nvim instance in a tmux split, communicating via server socket at `/tmp/nvim-claude-<session>`
3. Sources `diff-signs.lua` in nvim to show git diff markers in the gutter

**rename-window**: On session start → `tmux-rename.sh` renames the current tmux window to the project folder name in PascalCase.

## Development

Test locally by adding to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-tmux-toolkit": {
      "source": { "source": "directory", "path": "/path/to/claude-tmux-toolkit" }
    }
  },
  "enabledPlugins": {
    "nvim-sidebar@claude-tmux-toolkit": true,
    "rename-window@claude-tmux-toolkit": true
  }
}
```

Then restart Claude Code inside tmux. Any Write/Edit will trigger the hook.

## Dev Policy

### Versioning & Branching

- **Bug fix**: bump patch version (e.g. 1.0.1 → 1.0.2), commit directly to main
- **New feature**: bump minor version, reset patch to 0 (e.g. 1.0.2 → 1.1.0), create a PR — do NOT push to main directly
- Version must be updated in the affected plugin's `plugin.json:version`. Also update `marketplace.json` to keep in sync: the matching entry in `plugins[].version` must always match its `plugin.json:version`
- Apply version bumps automatically with every commit/PR — do not skip or ask

### Bash Scripts

- Structure bash scripts using modularized functions with descriptive names — avoid flat imperative style. The `main` function should read like a narrative of the script's logic.
- Avoid `[[ condition ]] && exit` inside functions under `set -e` — use `if/then` instead.
- Run `shellcheck` on all modified bash scripts before committing.

### Testing

- After modifying hook scripts, test by editing `test_file.txt` to trigger the PostToolUse hook directly.

## Requirements

- tmux, NeoVim 0.7+, jq
- Must run Claude Code inside a tmux session


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

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
