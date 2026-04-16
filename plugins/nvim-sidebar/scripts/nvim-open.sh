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

# Resolve script directory once at top level so functions can safely use SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

detect_tmux_session() {
    # Works even when TMUX env var is stripped by sandboxes (e.g. agent-safehouse),
    # as tmux finds the attached session via its server socket.
    TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null) || exit 0
}

find_target_window() {
    # Find the tmux window where Claude Code is running, so we target the
    # correct window even if the user has switched to a different one.
    #
    # Three methods, tried in order:
    #   1. Read window ID captured at SessionStart (most reliable — works in
    #      all sandbox environments since it uses only tmux + file I/O)
    #   2. $TMUX_PANE env var (works outside sandboxes)
    #   3. Walk process ancestors to find a controlling TTY (fallback)
    TARGET_WINDOW=""

    # Method 1: file written by capture-window.sh at SessionStart
    local key
    key=$(printf '%s' "$PWD" | shasum | cut -c1-8)
    local stored
    stored=$(cat "/tmp/nvim-claude-window-${TMUX_SESSION}-${key}" 2>/dev/null) || true
    if [[ -n "$stored" ]]; then
        # Verify the window still exists before using it
        if tmux display-message -t "$stored" -p '#{window_id}' &>/dev/null; then
            TARGET_WINDOW="$stored"
            return
        fi
    fi

    # Method 2: $TMUX_PANE — set by tmux in every pane, inherited by children
    if [[ -n "${TMUX_PANE:-}" ]]; then
        TARGET_WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null || true)
        if [[ -n "$TARGET_WINDOW" ]]; then
            return
        fi
    fi

    # Method 3: walk process ancestors to find a controlling TTY
    local pid=$$ ancestor_tty=""
    while [[ "$pid" -gt 1 ]]; do
        local t
        t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ') || true
        if [[ -n "$t" && "$t" != "?" && "$t" != "??" ]]; then
            ancestor_tty="$t"
            break
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || true
        if [[ -z "$pid" || "$pid" == "0" ]]; then
            break
        fi
    done

    if [[ -n "$ancestor_tty" ]]; then
        TARGET_WINDOW=$(tmux list-panes -a -F '#{pane_tty} #{window_id}' 2>/dev/null \
            | awk -v t="$ancestor_tty" '{
                name = $1
                sub(/^\/dev\//, "", name)
                sub(/^tty/, "", name)
                if (name == t) { print $2; exit }
            }')
    fi
}

parse_file_path() {
    FILE_PATH=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
    if [[ -z "$FILE_PATH" ]]; then exit 0; fi
}

init_env() {
    # Scope the socket per window so multiple Claude sessions in the same tmux
    # session (each in its own window) don't clobber each other's nvim server.
    # Window ids like "@3" become the "-3" suffix; if TARGET_WINDOW is unknown
    # we fall back to the plain session-scoped path (legacy behavior).
    local sock_suffix=""
    if [[ -n "${TARGET_WINDOW:-}" ]]; then
        sock_suffix="-${TARGET_WINDOW//@/}"
    fi
    SOCK="/tmp/nvim-claude-${TMUX_SESSION}${sock_suffix}"
    DIFF_SIGNS="${SCRIPT_DIR}/diff-signs.lua"

    # Full path to nvim — needed when tmux split-window inherits a minimal PATH
    NVIM=$(command -v nvim 2>/dev/null) || { echo "nvim not found" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
# Pane detection
# ---------------------------------------------------------------------------

scan_panes() {
    # Find the first nvim pane and first fish pane in the target tmux window.
    # Uses ASCII unit separator (0x1f) to avoid clashing with any command name.
    nvim_pane=""
    fish_pane=""
    local sep=$'\x1f'
    local list_panes_args=()

    if [[ -n "$TARGET_WINDOW" ]]; then
        list_panes_args=(-t "$TARGET_WINDOW")
    fi

    while IFS="$sep" read -r pane_id current_cmd; do
        if [[ "$current_cmd" == "nvim" && -z "$nvim_pane" ]]; then
            nvim_pane="$pane_id"
        elif [[ "$current_cmd" == "fish" && -z "$fish_pane" ]]; then
            fish_pane="$pane_id"
        fi
    done < <(tmux list-panes ${list_panes_args[@]+"${list_panes_args[@]}"} -F "#{pane_id}${sep}#{pane_current_command}")

    pane_count=$(tmux list-panes ${list_panes_args[@]+"${list_panes_args[@]}"} | wc -l | tr -d ' ')
}

# ---------------------------------------------------------------------------
# Actions — one function per scenario
# ---------------------------------------------------------------------------

open_in_existing_nvim() {
    # Reuse the running nvim instance to open the file and refresh diff signs.
    if [[ -S "$SOCK" ]]; then
        # Preferred: server RPC (non-disruptive, works in any nvim mode)
        "$NVIM" --server "$SOCK" --remote "$FILE_PATH" 2>/dev/null || true
        "$NVIM" --server "$SOCK" --remote-send "<Cmd>checktime<CR>" 2>/dev/null || true
        "$NVIM" --server "$SOCK" --remote-send "<Cmd>luafile ${DIFF_SIGNS}<CR>" 2>/dev/null || true
    else
        # Fallback: send keystrokes when the socket is missing.
        # Use :execute with fnameescape() so paths with spaces or special chars are safe.
        local escaped_file escaped_diff
        escaped_file=$(printf "%s" "$FILE_PATH" | sed "s/'/''/g")
        escaped_diff=$(printf "%s" "$DIFF_SIGNS" | sed "s/'/''/g")

        tmux send-keys -t "$nvim_pane" Escape \
            ":execute 'edit ' . fnameescape('${escaped_file}')" Enter \
            ':checktime' Enter \
            ":execute 'luafile ' . fnameescape('${escaped_diff}')" Enter
    fi
}

create_split_with_nvim() {
    # No split exists — create a horizontal split with a fresh nvim instance.
    rm -f "$SOCK"   # remove stale socket from a previous nvim that exited
    local split_args=(-h)
    if [[ -n "$TARGET_WINDOW" ]]; then
        split_args+=(-t "$TARGET_WINDOW")
    fi
    tmux split-window "${split_args[@]}" -- "$NVIM" --listen "$SOCK" -c "luafile ${DIFF_SIGNS}" "$FILE_PATH"
}

launch_nvim_in_fish_pane() {
    # An idle fish shell sits in the sidebar — start nvim inside it.
    # Use printf %q to safely escape paths with spaces or metacharacters.
    local cmd
    cmd=$(printf '%q --listen %q -c %q %q' "$NVIM" "$SOCK" "luafile ${DIFF_SIGNS}" "$FILE_PATH")
    tmux send-keys -t "$fish_pane" "$cmd" Enter
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    detect_tmux_session
    find_target_window
    parse_file_path
    init_env
    scan_panes

    # Too many splits already — don't add more complexity
    if [[ "$pane_count" -ge 3 ]]; then exit 0; fi

    if [[ -n "$nvim_pane" ]]; then
        open_in_existing_nvim
    elif [[ "$pane_count" -eq 1 ]]; then
        create_split_with_nvim
    elif [[ -n "$fish_pane" ]]; then
        launch_nvim_in_fish_pane
    fi
    # Otherwise: split exists but not fish — exit silently
}

main
