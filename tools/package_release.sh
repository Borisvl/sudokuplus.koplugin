#!/usr/bin/env bash
# Build and verify the installable Sudoku+ archive from declared repository inputs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
ARCHIVE="$OUTPUT_DIR/sudokuplus.koplugin.zip"
CHECKSUM="$ARCHIVE.sha256"
MSGFMT="${MSGFMT:-msgfmt}"

die() {
    printf 'package release: %s\n' "$*" >&2
    exit 1
}

for command in git python3 zip; do
    command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[[ -x "$MSGFMT" ]] || command -v "$MSGFMT" >/dev/null 2>&1 || die "required msgfmt command not found: $MSGFMT"

if [[ -z "${EXPECTED_VERSION:-}" ]]; then
    EXPECTED_VERSION="$(python3 - "$ROOT/sudokuplus.koplugin/sudokuplus/metadata.lua" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'^\s*version\s*=\s*"([^"]+)"\s*,?\s*$', text, re.MULTILINE)
if not match:
    raise SystemExit("cannot read plugin version")
print(match.group(1))
PY
)"
fi
[[ "$EXPECTED_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || die "EXPECTED_VERSION must be a stable semantic version"

mkdir -p "$OUTPUT_DIR"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sudoku-package.XXXXXX")"
cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT INT TERM HUP

while IFS= read -r -d '' source; do
    target="$STAGE/$source"
    mkdir -p "$(dirname "$target")"
    cp "$ROOT/$source" "$target"
done < <(git -C "$ROOT" ls-files -z sudokuplus.koplugin)

for legal_file in LICENSE COPYING.GPL-3.0 THIRD_PARTY_NOTICES; do
    [[ -f "$ROOT/$legal_file" ]] || die "missing required legal file: $legal_file"
    cp "$ROOT/$legal_file" "$STAGE/sudokuplus.koplugin/$legal_file"
done

while IFS= read -r -d '' po; do
    "$MSGFMT" --check --output-file="${po%.po}.mo" "$po"
done < <(find "$STAGE/sudokuplus.koplugin/l10n" -type f -name '*.po' -print0)

# Normalize mtimes and omit host metadata so the same tree has stable ZIP input.
find "$STAGE/sudokuplus.koplugin" -exec touch -t 198001010000 {} +
rm -f "$ARCHIVE" "$CHECKSUM"
(
    cd "$STAGE"
    LC_ALL=C find sudokuplus.koplugin -type f -print | LC_ALL=C sort | zip -X -q -9 "$ARCHIVE" -@
)

python3 "$ROOT/tools/verify_release_package.py" \
    --archive "$ARCHIVE" \
    --expected-version "$EXPECTED_VERSION" \
    --source-root "$ROOT" \
    --msgfmt "$MSGFMT"

if command -v sha256sum >/dev/null 2>&1; then
    HASH="$(sha256sum "$ARCHIVE" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
    HASH="$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)"
else
    die "required SHA-256 command not found"
fi
printf '%s  %s\n' "$HASH" "$(basename "$ARCHIVE")" > "$CHECKSUM"
printf 'Release package: %s\nChecksum: %s\n' "$ARCHIVE" "$CHECKSUM"
