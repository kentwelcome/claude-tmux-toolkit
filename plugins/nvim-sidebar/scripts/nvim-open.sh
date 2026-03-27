#!/usr/bin/env bash
#
# nvim-open.sh — Opens or reuses a NeoVim instance in a tmux split pane
#
# Called by Claude Code's PostToolUse hook after Write/Edit operations.
# Receives JSON on stdin with tool_input.file_path or tool_response.filePath.
#
# Behavior:
#   1. Nvim pane exists in current window → open file via server RPC (or send-keys fallback)
#   2. No split (single pane)             → create a new split and launch nvim
#   3. Split exists with idle fish pane   → launch nvim inside the fish pane
#   4. Split exists but not fish          → exit silently (don't interfere)
#

set -euo pipefail

# Detect tmux session. Works even when TMUX env var is stripped by sandboxes
# (e.g. agent-safehouse), as tmux finds the attached session via its server socket.
TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null) || exit 0

# Extract file path from hook JSON input
FILE_PATH=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[ -z "$FILE_PATH" ] && exit 0

# Unique nvim server socket per tmux session
SOCK="/tmp/nvim-claude-${TMUX_SESSION}"

# Lua script that places git diff signs in the current buffer's gutter
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIFF_SIGNS="${SCRIPT_DIR}/diff-signs.lua"

# Full path to nvim — needed when tmux split-window inherits a minimal PATH
NVIM=$(which nvim 2>/dev/null) || { echo "nvim not found" >&2; exit 1; }

# Scan panes in the current window for nvim and fish.
# Use ASCII unit separator (0x1f) to avoid clashing with any command name.
nvim_pane=""
fish_pane=""
SEP=$'\x1f'
while IFS="$SEP" read -r pane_id current_cmd; do
    if [[ "$current_cmd" == "nvim" && -z "$nvim_pane" ]]; then
        nvim_pane="$pane_id"
    elif [[ "$current_cmd" == "fish" && -z "$fish_pane" ]]; then
        fish_pane="$pane_id"
    fi
done < <(tmux list-panes -F "#{pane_id}${SEP}#{pane_current_command}")

pane_count=$(tmux list-panes | wc -l | tr -d ' ')

if [ -n "$nvim_pane" ]; then
    # Nvim pane exists — use server RPC to open file and refresh (non-disruptive)
    if [ -S "$SOCK" ]; then
        "$NVIM" --server "$SOCK" --remote "$FILE_PATH" 2>/dev/null || true
        "$NVIM" --server "$SOCK" --remote-send "<Cmd>checktime<CR>" 2>/dev/null || true
        "$NVIM" --server "$SOCK" --remote-send "<Cmd>luafile ${DIFF_SIGNS}<CR>" 2>/dev/null || true
    else
        # No socket — fall back to send-keys but use <Cmd> to avoid mode disruption
        tmux send-keys -t "$nvim_pane" Escape ":e $FILE_PATH" Enter ':checktime' Enter \
            ":luafile ${DIFF_SIGNS}" Enter
    fi
elif [ "$pane_count" -eq 1 ]; then
    # No split at all — create one with nvim using its full path.
    # Remove stale socket if present (left over from a previous nvim that exited).
    rm -f "$SOCK"
    tmux split-window -h "$NVIM --listen \"$SOCK\" -c \"luafile ${DIFF_SIGNS}\" \"$FILE_PATH\""
elif [ -n "$fish_pane" ]; then
    # Idle fish sidebar pane exists — launch nvim inside it (fish has full PATH)
    tmux send-keys -t "$fish_pane" "nvim --listen \"$SOCK\" -c \"luafile ${DIFF_SIGNS}\" \"$FILE_PATH\"" Enter
fi
# Otherwise: split exists but not fish — exit silently
