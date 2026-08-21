#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="$ROOT/tools/frontend_test_wrapper.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sudoku-frontend-wrapper.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

fail() {
    printf 'frontend_wrapper_test: %s\n' "$*" >&2
    exit 1
}

[[ -f "$WRAPPER" ]] || fail "missing $WRAPPER"

mkdir -p "$TMP/run" "$TMP/protected" "$TMP/sentinel"
touch "$TMP/sentinel/sudokuplus_save"

RESULT="$TMP/result"
# shellcheck disable=SC2016 # Variables expand in the wrapper's child shell.
SUDOKU_TEST_RUN_ROOT="$TMP/run" \
SUDOKU_PROTECTED_DATA_ROOTS="$TMP/protected" \
SUDOKU_TEST_SENTINEL_ROOT="$TMP/sentinel" \
RESULT="$RESULT" \
    "$WRAPPER" bash -c '
        test -n "$KO_HOME"
        test -f "$KO_HOME/.sudoku-test-home"
        case "$KO_HOME" in "$SUDOKU_TEST_RUN_ROOT"/*) ;; *) exit 20 ;; esac
        test "$KO_HOME" != "$SUDOKU_TEST_SENTINEL_ROOT"
        printf "%s" "$KO_HOME" > "$RESULT"
    '

HOME_PATH="$(<"$RESULT")"
[[ ! -e "$HOME_PATH" ]] || fail "per-test KO_HOME was not cleaned"
[[ -f "$TMP/sentinel/sudokuplus_save" ]] || fail "sentinel was modified"

set +e
# shellcheck disable=SC2016 # Variables expand in the wrapper's child shell.
SUDOKU_TEST_RUN_ROOT="$TMP/run" \
SUDOKU_PROTECTED_DATA_ROOTS="$TMP/protected" \
SUDOKU_TEST_SENTINEL_ROOT="$TMP/sentinel" \
RESULT="$RESULT" \
    "$WRAPPER" bash -c 'printf "%s" "$KO_HOME" > "$RESULT"; exit 23'
STATUS=$?
set -e
[[ "$STATUS" == "23" ]] || fail "wrapper did not preserve child failure status"
HOME_PATH="$(<"$RESULT")"
[[ ! -e "$HOME_PATH" ]] || fail "failed-test KO_HOME was not cleaned"

: > "$RESULT"
# shellcheck disable=SC2016 # Variables expand in the wrapper's child shell.
SUDOKU_TEST_RUN_ROOT="$TMP/run" \
SUDOKU_PROTECTED_DATA_ROOTS="$TMP/protected" \
SUDOKU_TEST_SENTINEL_ROOT="$TMP/sentinel" \
RESULT="$RESULT" \
    "$WRAPPER" bash -c 'printf "%s %s" "$KO_HOME" "$$" > "$RESULT"; exec sleep 60' &
WRAPPER_PID=$!
for _ in {1..100}; do
    [[ -s "$RESULT" ]] && break
    sleep 0.01
done
[[ -s "$RESULT" ]] || fail "interrupted child did not start"
read -r HOME_PATH CHILD_PID < "$RESULT" || true
kill -TERM "$WRAPPER_PID"
set +e
wait "$WRAPPER_PID"
STATUS=$?
set -e
[[ "$STATUS" == "143" ]] || fail "wrapper did not report TERM status"
[[ ! -e "$HOME_PATH" ]] || fail "interrupted-test KO_HOME was not cleaned"
if kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -KILL "$CHILD_PID"
    fail "interrupted child process survived"
fi

printf 'frontend_wrapper_test: ok\n'
