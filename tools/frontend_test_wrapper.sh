#!/usr/bin/env bash
set -euo pipefail

RUN_ROOT="${SUDOKU_TEST_RUN_ROOT:?SUDOKU_TEST_RUN_ROOT is required}"
[[ "$RUN_ROOT" == /* ]] || {
    printf 'frontend test wrapper: run root must be absolute\n' >&2
    exit 2
}
[[ $# -gt 0 ]] || {
    printf 'frontend test wrapper: child command is required\n' >&2
    exit 2
}

mkdir -p "$RUN_ROOT"
chmod 700 "$RUN_ROOT"
TEST_HOME="$(mktemp -d "$RUN_ROOT/ko-home.XXXXXX")"
chmod 700 "$TEST_HOME"
printf 'Sudoku+ isolated frontend test home\n' > "$TEST_HOME/.sudoku-test-home"

CHILD_PID=""

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [[ "${SUDOKU_KEEP_TEST_HOME:-0}" == "1" ]]; then
        printf 'frontend test wrapper: retained %s\n' "$TEST_HOME" >&2
    else
        rm -rf "$TEST_HOME"
    fi
    exit "$status"
}

interrupt() {
    local status="$1"
    trap - EXIT INT TERM HUP
    if [[ -n "$CHILD_PID" ]] && kill -0 "$CHILD_PID" 2>/dev/null; then
        kill -TERM "$CHILD_PID" 2>/dev/null || true
        wait "$CHILD_PID" 2>/dev/null || true
    fi
    if [[ "${SUDOKU_KEEP_TEST_HOME:-0}" == "1" ]]; then
        printf 'frontend test wrapper: retained %s\n' "$TEST_HOME" >&2
    else
        rm -rf "$TEST_HOME"
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'interrupt 130' INT
trap 'interrupt 143' TERM
trap 'interrupt 129' HUP

export KO_HOME="$TEST_HOME"
"$@" &
CHILD_PID=$!
wait "$CHILD_PID"
