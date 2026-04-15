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
  # Find the tmux window that owns the process running this hook, so we rename
  # the correct window even if the user has switched to a different window
  # before the hook fires.
  #
  # Cannot rely on `tty`: Claude Code may feed data on stdin, making it a pipe
  # where `tty` prints "not a tty". We resolve via two methods:
  #   1. $TMUX_PANE — set by tmux in every pane, inherited by all children
  #   2. Walk process ancestors to find a controlling TTY, then match it to a
  #      tmux pane (fallback for sandboxes that strip TMUX_PANE)
  if [ -n "${TMUX_PANE:-}" ]; then
    local window_id
    window_id=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null || true)
    if [ -n "$window_id" ]; then
      echo "$window_id"
      return
    fi
  fi

  local pid=$$ ancestor_tty=""
  while [ "$pid" -gt 1 ]; do
    local t
    t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$t" ] && [ "$t" != "?" ] && [ "$t" != "??" ]; then
      ancestor_tty="$t"
      break
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -z "$pid" ] || [ "$pid" = "0" ]; then
      break
    fi
  done

  if [ -n "$ancestor_tty" ]; then
    # tmux pane_tty is /dev/ttys001 (macOS) or /dev/pts/0 (Linux);
    # ps -o tty= outputs "s001" or "pts/0". Strip /dev/ and the leading
    # "tty" prefix from tmux's value before comparing.
    local window_id
    window_id=$(tmux list-panes -a -F '#{pane_tty} #{window_id}' 2>/dev/null \
      | awk -v t="$ancestor_tty" '{
          name = $1
          sub(/^\/dev\//, "", name)
          sub(/^tty/, "", name)
          if (name == t) { print $2; exit }
        }')
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
