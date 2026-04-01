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

find_window_id() {
  # Find the tmux window that owns our TTY, so we rename the correct window
  # even if the user has switched to a different window before this hook fires.
  local my_tty
  my_tty=$(tty 2>/dev/null) || true

  if [ -n "$my_tty" ]; then
    local window_id
    window_id=$(tmux list-panes -a -F '#{pane_tty} #{window_id}' \
      | awk -v tty="$my_tty" '$1 == tty { print $2; exit }')
    if [ -n "$window_id" ]; then
      echo "$window_id"
      return
    fi
  fi

  # Fallback: use the active window (original behavior)
  echo ""
}

folder_to_pascal_case() {
  local folder_name
  folder_name=$(basename "$PWD")

  echo "$folder_name" | sed -E 's/[-_ ]+/ /g' | awk '{
      for (i=1; i<=NF; i++) {
          printf "%s", toupper(substr($i,1,1)) substr($i,2)
      }
      print ""
  }'
}

main() {
  local window_id camel
  window_id=$(find_window_id)
  camel=$(folder_to_pascal_case)

  if [ -n "$window_id" ]; then
    tmux rename-window -t "$window_id" "$camel"
  else
    tmux rename-window "$camel"
  fi
}

main
