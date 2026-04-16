#!/usr/bin/env bash
#
# capture-window.sh — Stores the current tmux window ID at session start
#
# Called by the SessionStart hook. At that moment, the active tmux window IS
# the window where Claude Code was launched, so `tmux display-message` returns
# the correct target. PostToolUse hooks (nvim-open.sh) read this file to
# target the right window — even when sandboxes block $TMUX_PANE and `ps`.

set -euo pipefail

SESSION=$(tmux display-message -p '#S' 2>/dev/null) || exit 0
WINDOW_ID=$(tmux display-message -p '#{window_id}' 2>/dev/null) || exit 0

# Key by session + PWD hash so multiple Claude sessions in different
# directories each get their own window mapping.
KEY=$(printf '%s' "$PWD" | shasum | cut -c1-8)
echo "$WINDOW_ID" > "/tmp/nvim-claude-window-${SESSION}-${KEY}"
