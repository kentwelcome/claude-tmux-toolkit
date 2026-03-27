#!/usr/bin/env bash
#
# tmux-rename.sh — Renames the tmux window to the current folder name in PascalCase
#
# Called by Claude Code's SessionStart hook.
# Converts folder name: removes spaces, hyphens, underscores and applies PascalCase.
#   e.g. "claude-nvim-sidebar" → "ClaudeNvimSidebar"
#        "my_cool project"     → "MyCoolProject"

set -euo pipefail

# Exit if not inside tmux
if [ -z "${TMUX:-}" ]; then
  # Hook subprocesses may not inherit $TMUX; detect via pane ID
  if ! tmux display-message -p '#{pane_id}' &>/dev/null; then
    exit 0
  fi
fi

# Get the current folder name
FOLDER_NAME=$(basename "$PWD")

# Convert to PascalCase: split on [-_ ], capitalize first letter of each word
CAMEL=$(echo "$FOLDER_NAME" | sed -E 's/[-_ ]+/ /g' | awk '{
    for (i=1; i<=NF; i++) {
        printf "%s", toupper(substr($i,1,1)) substr($i,2)
    }
    print ""
}')

# Rename the current tmux window
tmux rename-window "$CAMEL"
