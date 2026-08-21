#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sudoku-environment.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

fail() {
    printf 'environment_test: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$TMP/bin" "$TMP/prefix/opt/gettext/bin"
cat > "$TMP/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_BREW_PREFIX"
EOF
cat > "$TMP/prefix/opt/gettext/bin/msgfmt" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/bin/brew" "$TMP/prefix/opt/gettext/bin/msgfmt"

if ! resolved="$(
    PATH="$TMP/bin:/usr/bin:/bin" TEST_BREW_PREFIX="$TMP/prefix" \
        bash -c 'source "$1"; command -v msgfmt' _ "$ROOT/env.sh"
)"; then
    fail "env.sh did not expose Homebrew gettext"
fi
[[ "$resolved" == "$TMP/prefix/opt/gettext/bin/msgfmt" ]] || fail "env.sh selected the wrong msgfmt"

# shellcheck disable=SC2016 # Match the literal ROOT reference in run.sh.
grep -Fq 'source "$ROOT/env.sh"' "$ROOT/tests/tooling/run.sh" \
    || fail "the standalone tooling runner must source env.sh"

printf 'environment_test: ok\n'
