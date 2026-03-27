# claude-nvim-sidebar

A Claude Code plugin that auto-opens NeoVim in a tmux split pane when files are edited.

## Project Structure

```
.claude-plugin/                    # Marketplace registry (marketplace.json)
plugins/tmux-toolkit/
  .claude-plugin/plugin.json       # Plugin metadata
  hooks/hooks.json                 # PostToolUse hook definition — triggers on Write|Edit
  scripts/nvim-open.sh             # Main hook script — manages tmux panes and nvim instances
  scripts/diff-signs.lua           # Git diff gutter signs — sourced by nvim after each edit
  scripts/tmux-rename.sh           # SessionStart hook — renames tmux window to PascalCase
```

## How the Hook Works

1. Claude Code calls Write or Edit → `hooks.json` triggers `nvim-open.sh`
2. `nvim-open.sh` reads JSON from stdin (`tool_input.file_path` or `tool_response.filePath`)
3. Opens or reuses a nvim instance in a tmux split, communicating via server socket at `/tmp/nvim-claude-<session>`
4. Sources `diff-signs.lua` in nvim to show git diff markers in the gutter

## Development

Test locally by adding to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-tmux-toolkit": {
      "source": { "source": "directory", "path": "/path/to/claude-nvim-sidebar" }
    }
  },
  "enabledPlugins": { "tmux-toolkit@claude-tmux-toolkit": true }
}
```

Then restart Claude Code inside tmux. Any Write/Edit will trigger the hook.

## Dev Policy

### Versioning & Branching

- **Bug fix**: bump patch version (e.g. 1.0.1 → 1.0.2), commit directly to main
- **New feature**: bump minor version, reset patch to 0 (e.g. 1.0.2 → 1.1.0), create a PR — do NOT push to main directly
- Version must be updated in `plugin.json:version`. Also update `marketplace.json` to keep in sync: `plugins[0].version` and `metadata.version` must always match `plugin.json:version`
- Apply version bumps automatically with every commit/PR — do not skip or ask

## Requirements

- tmux, NeoVim 0.7+, jq
- Must run Claude Code inside a tmux session
