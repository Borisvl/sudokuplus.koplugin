#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGER="$ROOT/tools/package_release.sh"
VERIFIER="$ROOT/tools/verify_release_package.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sudoku-package.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

fail() {
    printf 'package_release_test: %s\n' "$*" >&2
    exit 1
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

[[ -f "$VERIFIER" ]] || fail "missing $VERIFIER"

VERSION="$(python3 - "$ROOT/sudokuplus.koplugin/sudokuplus/metadata.lua" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
print(re.search(r'\bversion\s*=\s*"([^"]+)"', text).group(1))
PY
)"
OUTPUT_DIR="$TMP/out" EXPECTED_VERSION="$VERSION" "$PACKAGER"
ARCHIVE="$TMP/out/sudokuplus.koplugin.zip"
CHECKSUM="$ARCHIVE.sha256"

[[ -s "$ARCHIVE" ]] || fail "package archive was not created"
[[ -s "$CHECKSUM" ]] || fail "checksum sidecar was not created"
python3 "$VERIFIER" --archive "$ARCHIVE" --expected-version "$VERSION" --source-root "$ROOT"

EXPECTED_HASH="$(cut -d ' ' -f 1 "$CHECKSUM")"
if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_HASH="$(sha256sum "$ARCHIVE" | cut -d ' ' -f 1)"
else
    ACTUAL_HASH="$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)"
fi
[[ "$EXPECTED_HASH" == "$ACTUAL_HASH" ]] || fail "checksum does not match archive"

python3 - "$ARCHIVE" "$TMP/no-license.zip" <<'PY'
import sys
import zipfile

source, target = sys.argv[1:]
with zipfile.ZipFile(source) as src, zipfile.ZipFile(target, "w") as dst:
    for info in src.infolist():
        if info.filename != "sudokuplus.koplugin/LICENSE":
            dst.writestr(info, src.read(info.filename))
PY
expect_failure python3 "$VERIFIER" --archive "$TMP/no-license.zip" --expected-version "$VERSION" --source-root "$ROOT"

python3 - "$ARCHIVE" "$TMP/unexpected.zip" <<'PY'
import sys
import zipfile

source, target = sys.argv[1:]
with zipfile.ZipFile(source) as src, zipfile.ZipFile(target, "w") as dst:
    for info in src.infolist():
        dst.writestr(info, src.read(info.filename))
    dst.writestr("sudokuplus.koplugin/unexpected.tmp", "not allowed")
PY
expect_failure python3 "$VERIFIER" --archive "$TMP/unexpected.zip" --expected-version "$VERSION" --source-root "$ROOT"

python3 - "$ARCHIVE" "$TMP/altered-license.zip" <<'PY'
import sys
import zipfile

source, target = sys.argv[1:]
with zipfile.ZipFile(source) as src, zipfile.ZipFile(target, "w") as dst:
    for info in src.infolist():
        data = src.read(info.filename)
        if info.filename == "sudokuplus.koplugin/LICENSE":
            data = data.replace(b"free software", b"free softwarE", 1)
        dst.writestr(info, data)
PY
expect_failure python3 "$VERIFIER" --archive "$TMP/altered-license.zip" --expected-version "$VERSION" --source-root "$ROOT"

python3 - "$ARCHIVE" "$TMP/altered-source.zip" <<'PY'
import sys
import zipfile

source, target = sys.argv[1:]
with zipfile.ZipFile(source) as src, zipfile.ZipFile(target, "w") as dst:
    for info in src.infolist():
        data = src.read(info.filename)
        if info.filename == "sudokuplus.koplugin/sudokuplus/game.lua":
            data += b"\n-- altered after packaging\n"
        dst.writestr(info, data)
PY
expect_failure python3 "$VERIFIER" --archive "$TMP/altered-source.zip" --expected-version "$VERSION" --source-root "$ROOT"

expect_failure env OUTPUT_DIR="$TMP/no-msgfmt" EXPECTED_VERSION="$VERSION" MSGFMT="/does/not/exist" "$PACKAGER"

printf 'package_release_test: ok\n'
