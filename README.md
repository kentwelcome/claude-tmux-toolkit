# claude-tmux-toolkit

A collection of [Claude Code](https://claude.ai/claude-code) plugins for tmux productivity.

## Plugins

### nvim-sidebar

Auto-opens NeoVim in a tmux split pane when Claude edits files — giving you a real-time sidebar view of every change.

- **Auto-open**: NeoVim opens in a tmux horizontal split on the first file edit
- **Real-time sync**: File content refreshes instantly when Claude makes changes
- **Diff signs**: Git diff markers (`+`/`-`) in the gutter show exactly which lines were added or removed
- **Multi-file**: New files open as buffers in the same NeoVim instance (`:bn`/`:bp` to switch)
- **Smart reuse**: Detects existing splits and NeoVim instances — never creates duplicates
- **tmux-aware**: Only activates inside tmux sessions; no-op otherwise

### rename-window

Renames the tmux window to the current project folder name in PascalCase on session start.

- e.g. `claude-tmux-toolkit` → `ClaudeTmuxToolkit`

## Demo

![Claude Code + NeoVim sidebar with diff signs](assets/demo.png)

## Requirements

- [tmux](https://github.com/tmux/tmux)
- [NeoVim](https://neovim.io/) (0.7+ for `--listen`/`--server`/`--remote`) — required for `nvim-sidebar`
- [jq](https://jqlang.github.io/jq/) — required for `nvim-sidebar`
- [Claude Code](https://claude.ai/claude-code)

## Installation

### Using `/plugin marketplace add` command (recommended)

Inside Claude Code, run:

```
/plugin marketplace add kentwelcome/claude-tmux-toolkit
```

Then install individual plugins:

```bash
claude plugin install nvim-sidebar@claude-tmux-toolkit --scope user
claude plugin install rename-window@claude-tmux-toolkit --scope user
```

### Manual installation

**Step 1** — Register the marketplace in your `~/.claude/settings.json` (user scope) or `.claude/settings.json` (project scope):

```json
{
  "extraKnownMarketplaces": {
    "claude-tmux-toolkit": {
      "source": {
        "source": "github",
        "repo": "kentwelcome/claude-tmux-toolkit"
      }
    }
  }
}
```

**Step 2** — Install the plugins:

```bash
claude plugin install nvim-sidebar@claude-tmux-toolkit --scope user
claude plugin install rename-window@claude-tmux-toolkit --scope user
```

### From local path (for development)

**Step 1** — Clone the repo:

```bash
git clone https://github.com/kentwelcome/claude-tmux-toolkit.git
```

**Step 2** — Add to `~/.claude/settings.json` (user scope) or `.claude/settings.json` (project scope):

```json
{
  "extraKnownMarketplaces": {
    "claude-tmux-toolkit": {
      "source": {
        "source": "directory",
        "path": "/absolute/path/to/claude-tmux-toolkit"
      }
    }
  },
  "enabledPlugins": {
    "nvim-sidebar@claude-tmux-toolkit": true,
    "rename-window@claude-tmux-toolkit": true
  }
}
```

**Step 3** — Start Claude Code inside a tmux session and reload plugins:

```
/reload-plugins
```

**Step 4** — Trigger a file edit (Write or Edit) to verify the nvim sidebar opens.

#### Development workflow

After making changes to scripts or hooks:

1. Edit the files in the repo (e.g. `plugins/nvim-sidebar/scripts/nvim-open.sh`)
2. Run `/reload-plugins` inside Claude Code to pick up hook changes
3. Trigger a file edit to test — the hooks run the scripts directly from your local repo path, so script changes take effect immediately without reloading

## Recommended NeoVim Config

For the best experience with `nvim-sidebar`, add this to your NeoVim config so files auto-reload when changed externally:

```lua
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
    command = "silent! checktime",
})
```

Also ensure tmux has focus events enabled in your `.tmux.conf`:

```tmux
set-option -g focus-events on
```

## How nvim-sidebar Works

The plugin registers a `PostToolUse` hook on `Write` and `Edit` tool calls:

1. **First file edit** — Opens a tmux horizontal split with NeoVim listening on a server socket (`/tmp/nvim-claude-<session>`)
2. **Same file edited again** — Sends `:checktime` to the existing NeoVim pane to refresh
3. **Different file edited** — Opens the file as a new buffer in the existing NeoVim via `--remote`
4. **Existing split detected** — Reuses it instead of creating a new one
5. **After every edit** — Runs `git diff` and places `+`/`-` signs in the gutter via NeoVim's sign API

## NeoVim Keybindings (for buffer navigation)

| Key | Action |
|-----|--------|
| `:bn` | Next buffer |
| `:bp` | Previous buffer |
| `:ls` | List all buffers |
| `:b <name>` | Switch to buffer by name |

## Uninstall

```bash
claude plugin uninstall nvim-sidebar@claude-tmux-toolkit
claude plugin uninstall rename-window@claude-tmux-toolkit
```

Then remove the `claude-tmux-toolkit` entry from `extraKnownMarketplaces` in your settings.json.

## License

MIT
