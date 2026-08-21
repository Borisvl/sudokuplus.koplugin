#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT/tools/validate_release.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sudoku-release-validation.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

fail() {
    printf 'release_validation_test: %s\n' "$*" >&2
    exit 1
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

[[ -f "$VALIDATOR" ]] || fail "missing $VALIDATOR"

cat > "$TMP/meta.lua" <<'EOF'
return { name = "sudokuplus", version = "1.2.3" }
EOF
cat > "$TMP/changelog.md" <<'EOF'
# Changelog

## [1.2.3] - 2026-08-21

- Release note.

## [1.2.2] - 2026-08-20

- Older note.
EOF

"$VALIDATOR" files v1.2.3 "$TMP/meta.lua" "$TMP/changelog.md" "$TMP/notes.md"
grep -q 'Release note' "$TMP/notes.md" || fail "release notes were not extracted"
expect_failure "$VALIDATOR" files 1.2.3 "$TMP/meta.lua" "$TMP/changelog.md" "$TMP/notes.md"
expect_failure "$VALIDATOR" files v01.2.3 "$TMP/meta.lua" "$TMP/changelog.md" "$TMP/notes.md"
expect_failure "$VALIDATOR" files v1.2.4 "$TMP/meta.lua" "$TMP/changelog.md" "$TMP/notes.md"

mkdir "$TMP/repo"
git -C "$TMP/repo" init -q -b main
printf 'first\n' > "$TMP/repo/file"
git -C "$TMP/repo" add file
git -C "$TMP/repo" -c user.name=Test -c user.email=test@example.com commit -q -m first
git -C "$TMP/repo" -c user.name=Test -c user.email=test@example.com tag -a v1.2.3 -m v1.2.3
SHA="$(git -C "$TMP/repo" rev-parse HEAD)"
"$VALIDATOR" git v1.2.3 "$SHA" main "$TMP/repo"

git -C "$TMP/repo" tag v1.2.4
"$VALIDATOR" git v1.2.4 "$SHA" main "$TMP/repo"
git -C "$TMP/repo" tag lightweight
expect_failure "$VALIDATOR" git lightweight "$SHA" main "$TMP/repo"
expect_failure "$VALIDATOR" git v1.2.3 "0000000000000000000000000000000000000000" main "$TMP/repo"

printf 'release_validation_test: ok\n'
