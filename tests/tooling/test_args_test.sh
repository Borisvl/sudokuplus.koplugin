#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$ROOT/tools/check_test_args.sh"

fail() {
    printf 'test_args_test: %s\n' "$*" >&2
    exit 1
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

[[ -x "$CHECKER" ]] || fail "missing executable $CHECKER"

"$CHECKER" --frontend -f hints sudoku_view_spec.lua
expect_failure "$CHECKER" --wrapper=/usr/bin/true
expect_failure "$CHECKER" -w/usr/bin/true
expect_failure "$CHECKER" --meson=--wrapper=/usr/bin/true
expect_failure "$CHECKER" --busted=--filter=anything
expect_failure "$CHECKER" --gdb
expect_failure "$CHECKER" -g

printf 'test_args_test: ok\n'
