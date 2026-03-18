#!/usr/bin/env bash
#
# nvim-open.sh — Opens or reuses a NeoVim instance in a tmux split pane
#
# Called by Claude Code's PostToolUse hook after Write/Edit operations.
# Receives JSON on stdin with tool_input.file_path or tool_response.filePath.
#
# Behavior:
#   1. First edit     → opens a tmux horizontal split with nvim (server mode)
#   2. Same file edit → sends :checktime to refresh nvim
#   3. New file edit  → opens file as a new buffer in the existing nvim
#   4. Existing split → reuses it instead of creating a new one
#

set -euo pipefail

# Exit if not inside tmux
[ -z "${TMUX:-}" ] && exit 0

# Extract file path from hook JSON input
FILE_PATH=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[ -z "$FILE_PATH" ] && exit 0

# Unique nvim server socket per tmux session
TMUX_SESSION=$(tmux display-message -p '#S')
SOCK="/tmp/nvim-claude-${TMUX_SESSION}"

# Lua script that places git diff signs in the current buffer's gutter
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIFF_SIGNS="${SCRIPT_DIR}/diff-signs.lua"

# Find an existing nvim pane in the current window
nvim_pane=""
for pane_id in $(tmux list-panes -F '#{pane_id}'); do
    ppid=$(tmux display-message -t "$pane_id" -p '#{pane_pid}')
    if pgrep -fP "$ppid" nvim >/dev/null 2>&1; then
        nvim_pane="$pane_id"
        break
    fi
done

if [ -n "$nvim_pane" ]; then
    # Nvim pane exists — use server RPC to open file and refresh (non-disruptive)
    if [ -S "$SOCK" ]; then
        nvim --server "$SOCK" --remote "$FILE_PATH" 2>/dev/null || true
        nvim --server "$SOCK" --remote-send "<Cmd>checktime<CR>" 2>/dev/null || true
        nvim --server "$SOCK" --remote-send "<Cmd>luafile ${DIFF_SIGNS}<CR>" 2>/dev/null || true
    else
        # No socket — fall back to send-keys but use <Cmd> to avoid mode disruption
        tmux send-keys -t "$nvim_pane" Escape ":e $FILE_PATH" Enter ':checktime' Enter \
            ":luafile ${DIFF_SIGNS}" Enter
    fi
elif [ "$(tmux list-panes | wc -l)" -gt 1 ]; then
    # A split pane exists but no nvim — launch nvim in the right pane
    tmux send-keys -t '{right}' "nvim --listen \"$SOCK\" -c \"luafile ${DIFF_SIGNS}\" \"$FILE_PATH\"" Enter
else
    # No split at all — create one with nvim
    tmux split-window -h "nvim --listen \"$SOCK\" -c \"luafile ${DIFF_SIGNS}\" \"$FILE_PATH\""
fi
