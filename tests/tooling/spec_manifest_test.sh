#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/tools/spec_manifest.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sudoku-spec-manifest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

fail() {
    printf 'spec_manifest_test: %s\n' "$*" >&2
    exit 1
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

[[ -f "$TOOL" ]] || fail "missing $TOOL"

mkdir -p "$TMP/unit"
touch "$TMP/unit/alpha_spec.lua" "$TMP/unit/beta_spec.lua"
cat > "$TMP/unit/beta_spec.lua" <<'EOF'
local guard = require("sudoku_frontend_test_guard")
guard.install()
require("commonrequire")
EOF

printf 'core %s\nfrontend %s\n' \
    "$TMP/unit/alpha_spec.lua" "$TMP/unit/beta_spec.lua" > "$TMP/valid.txt"
"$TOOL" check "$TMP/valid.txt" "$TMP/unit"

cat > "$TMP/unit/alpha_spec.lua" <<'EOF'
local widget = require 'ui/widget/widget'
return widget
EOF
expect_failure "$TOOL" check "$TMP/valid.txt" "$TMP/unit"
: > "$TMP/unit/alpha_spec.lua"

printf 'core %s\n' "$TMP/unit/alpha_spec.lua" > "$TMP/missing.txt"
expect_failure "$TOOL" check "$TMP/missing.txt" "$TMP/unit"

printf 'core %s\nfrontend %s\ncore %s\n' \
    "$TMP/unit/alpha_spec.lua" "$TMP/unit/beta_spec.lua" "$TMP/unit/alpha_spec.lua" > "$TMP/duplicate.txt"
expect_failure "$TOOL" check "$TMP/duplicate.txt" "$TMP/unit"

printf 'browser %s\nfrontend %s\n' \
    "$TMP/unit/alpha_spec.lua" "$TMP/unit/beta_spec.lua" > "$TMP/category.txt"
expect_failure "$TOOL" check "$TMP/category.txt" "$TMP/unit"

printf 'frontend %s\ncore %s\n' \
    "$TMP/unit/beta_spec.lua" "$TMP/unit/alpha_spec.lua" > "$TMP/unsorted.txt"
expect_failure "$TOOL" check "$TMP/unsorted.txt" "$TMP/unit"

cat > "$TMP/unit/beta_spec.lua" <<'EOF'
require("commonrequire")
EOF
expect_failure "$TOOL" check "$TMP/valid.txt" "$TMP/unit"

cat > "$TMP/unit/beta_spec.lua" <<'EOF'
-- local guard = require("sudoku_frontend_test_guard")
-- guard.install()
require("commonrequire")
EOF
expect_failure "$TOOL" check "$TMP/valid.txt" "$TMP/unit"

"$TOOL" check "$ROOT/tests/spec-manifest.txt" "$ROOT/tests/unit"
[[ "$("$TOOL" list core "$ROOT/tests/spec-manifest.txt" | wc -l | tr -d ' ')" == "39" ]] \
    || fail "core manifest must contain 39 specs"
[[ "$("$TOOL" list frontend "$ROOT/tests/spec-manifest.txt" | wc -l | tr -d ' ')" == "9" ]] \
    || fail "frontend manifest must contain 9 specs"

printf 'spec_manifest_test: ok\n'
