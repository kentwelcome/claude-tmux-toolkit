#!/usr/bin/env bash
#
# e2e tests for the nvim-sidebar hook (nvim-open.sh)
#
# Each test runs in an isolated tmux session to avoid side effects.
# Requires: tmux, nvim, fish, jq
#
# Usage: bash plugins/nvim-sidebar/tests/e2e.sh

set -euo pipefail

SESSION="nvim-sidebar-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../scripts/nvim-open.sh"
TEST_FILE="/tmp/nvim-sidebar-test-file.txt"
TEST_FILE2="/tmp/nvim-sidebar-test-file2.txt"
SOCK="/tmp/nvim-claude-${SESSION}"

PASS=0
FAIL=0

# ── helpers ───────────────────────────────────────────────────────────────────

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

setup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -f "$SOCK"
    touch "$TEST_FILE" "$TEST_FILE2"
    # Force bash as the first pane to match the real use case (safehouse runs Claude in bash)
    tmux new-session -d -s "$SESSION" bash
}

teardown() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -f "$SOCK" "$TEST_FILE" "$TEST_FILE2"
}

# Run the hook in the context of the test session (sets TMUX correctly)
#
# Real Claude Code hooks inherit TMUX_PANE from the shell running Claude.
# `tmux run-shell` does NOT export TMUX_PANE, so we set it explicitly to
# match what the hook would see under real usage.
run_hook() {
    local file="${1:-$TEST_FILE}"
    local target_window="${2:-${SESSION}:0}"
    local pane_id
    pane_id=$(tmux display-message -t "${target_window}.0" -p '#{pane_id}')
    local json
    json='{"tool_input":{"file_path":"'"$file"'"}}'
    tmux run-shell -t "${target_window}" \
        "export TMUX_PANE='$pane_id'; echo '$json' | $HOOK 2>&1 || true"
}

pane_count() {
    tmux list-panes -t "${SESSION}:0" 2>/dev/null | wc -l | tr -d ' '
}

pane_cmd() {
    tmux display-message -t "${SESSION}:0.$1" -p '#{pane_current_command}' 2>/dev/null || echo ""
}

# Poll until pane count reaches expected value or timeout
wait_for_count() {
    local expected="$1"
    local timeout="${2:-5}"
    local i
    for i in $(seq 1 "$timeout"); do
        [ "$(pane_count)" -eq "$expected" ] && return 0
        sleep 1
    done
    return 1
}

# Poll until pane at index has expected current command or timeout
wait_for_pane_cmd() {
    local idx="$1"
    local expected="$2"
    local timeout="${3:-5}"
    local i
    for i in $(seq 1 "$timeout"); do
        [ "$(pane_cmd "$idx")" = "$expected" ] && return 0
        sleep 1
    done
    return 1
}

# Poll until nvim socket file exists or timeout
wait_for_socket() {
    local timeout="${1:-10}"
    local i
    for i in $(seq 1 "$timeout"); do
        [ -S "$SOCK" ] && return 0
        sleep 1
    done
    return 1
}

# ── test cases ────────────────────────────────────────────────────────────────

# Test 1: Single pane — hook should create a new split and launch nvim
test_no_split() {
    echo "Test 1: No split panel → creates nvim split"
    setup

    run_hook
    if wait_for_count 2 5 && wait_for_pane_cmd 1 nvim 5; then
        pass "new split created with nvim"
    else
        fail "expected 2 panes with nvim — got $(pane_count) pane(s), pane 1: $(pane_cmd 1)"
    fi

    teardown
}

# Test 2: Split with idle fish pane — hook should launch nvim inside it
test_fish_split() {
    echo "Test 2: One split with fish shell → launches nvim inside it"
    setup
    tmux split-window -t "${SESSION}:0" -h fish
    wait_for_pane_cmd 1 fish 5 || true  # wait for fish to be ready

    run_hook
    if wait_for_pane_cmd 1 nvim 5; then
        pass "nvim launched inside fish pane"
    else
        fail "expected fish pane to become nvim — got $(pane_cmd 1)"
    fi

    teardown
}

# Test 3: Split with non-fish shell — hook should exit silently
test_non_fish_split() {
    echo "Test 3: One split with non-fish shell → silent"
    setup
    tmux split-window -t "${SESSION}:0" -h bash
    sleep 1  # let bash settle

    run_hook
    sleep 2  # give hook time to complete and verify nothing changed
    local count cmd1
    count=$(pane_count)
    cmd1=$(pane_cmd 1)
    if [ "$count" -eq 2 ] && [ "$cmd1" != "nvim" ]; then
        pass "exited silently, no nvim launched"
    else
        fail "expected 2 non-nvim panes — got count=$count pane1=$cmd1"
    fi

    teardown
}

# Test 4: Split with nvim already open — hook should update via RPC
test_nvim_already_open() {
    echo "Test 4: One split with nvim open → reuses via RPC"
    setup
    local nvim_bin
    nvim_bin=$(which nvim)
    tmux split-window -t "${SESSION}:0" -h "$nvim_bin --listen $SOCK $TEST_FILE"
    if ! wait_for_socket 10; then
        fail "nvim socket not created in time — skipping"
        teardown
        return
    fi

    run_hook "$TEST_FILE2"
    sleep 1
    local count cmd1
    count=$(pane_count)
    cmd1=$(pane_cmd 1)
    if [ "$count" -eq 2 ] && [ "$cmd1" = "nvim" ]; then
        pass "reused existing nvim via RPC, no new split created"
    else
        fail "expected 2 panes with nvim — got count=$count pane1=$cmd1"
    fi

    teardown
}

# Test 5: Two splits (3 panes) — hook should exit silently
test_two_splits() {
    echo "Test 5: Two or more split panels → silent"
    setup
    tmux split-window -t "${SESSION}:0" -h bash
    tmux split-window -t "${SESSION}:0" bash
    sleep 1  # let panes settle

    run_hook
    sleep 2  # give hook time to complete and verify nothing changed
    local count
    count=$(pane_count)
    if [ "$count" -eq 3 ]; then
        pass "exited silently, pane count unchanged"
    else
        fail "expected 3 panes unchanged — got $count"
    fi

    teardown
}

# Test 6: Hook fires in window 0 while user is viewing window 1 — split must
# land in window 0 (the Claude window), not in the currently-active window 1.
# This guards against the `tty` detection bug, where stdin is a pipe and the
# hook used to fall back to "active window" targeting.
test_multi_window() {
    echo "Test 6: Hook from Claude in window 0 while window 1 is active → split opens in window 0"
    setup
    tmux new-window -t "${SESSION}" -d bash    # create window 1 (background)
    tmux select-window -t "${SESSION}:1"       # focus window 1 — the decoy

    run_hook                                    # run-shell -t sess:0 → TMUX_PANE = window 0's pane
    sleep 3

    local count_w0 count_w1
    count_w0=$(tmux list-panes -t "${SESSION}:0" 2>/dev/null | wc -l | tr -d ' ')
    count_w1=$(tmux list-panes -t "${SESSION}:1" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$count_w0" -eq 2 ] && [ "$count_w1" -eq 1 ]; then
        pass "split created in window 0 (Claude's window), window 1 untouched"
    else
        fail "expected w0=2 panes, w1=1 pane — got w0=$count_w0 w1=$count_w1"
    fi

    teardown
}

# ── runner ────────────────────────────────────────────────────────────────────

echo ""
echo "nvim-sidebar e2e tests"
echo "══════════════════════"

test_no_split
echo ""
test_fish_split
echo ""
test_non_fish_split
echo ""
test_nvim_already_open
echo ""
test_two_splits
echo ""
test_multi_window

echo ""
echo "══════════════════════"
printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo ""

[ "$FAIL" -eq 0 ]
