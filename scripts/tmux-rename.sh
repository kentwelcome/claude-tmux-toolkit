#!/usr/bin/env bash
#
# tmux-rename.sh — Renames the tmux window to the current folder name in camelCase
#
# Called by Claude Code's SessionStart hook.
# Converts folder name: removes spaces, hyphens, underscores and applies camelCase.
#   e.g. "claude-nvim-sidebar" → "claudeNvimSidebar"
#        "my_cool project"     → "myCoolProject"

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

# Convert to camelCase: split on [-_ ], capitalize first letter of each word except the first
CAMEL=$(echo "$FOLDER_NAME" | sed -E 's/[-_ ]+/ /g' | awk '{
    for (i=1; i<=NF; i++) {
        if (i == 1) {
            printf "%s", tolower(substr($i,1,1)) substr($i,2)
        } else {
            printf "%s", toupper(substr($i,1,1)) substr($i,2)
        }
    }
    print ""
}')

# Rename the current tmux window
tmux rename-window "$CAMEL"
