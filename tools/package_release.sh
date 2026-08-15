#!/usr/bin/env bash
# Creates a clean release zip archive of sudokuplus.koplugin ready for deployment or GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
PLUGIN_SOURCE="$PROJECT_ROOT/sudokuplus.koplugin"
DIST_DIR="$PROJECT_ROOT/dist"
STAGE_DIR="$DIST_DIR/stage"
ZIP_OUTPUT="$DIST_DIR/sudokuplus.koplugin.zip"

printf "==> Preparing Sudoku+ release package...\n"

rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR/sudokuplus.koplugin"

# Copy plugin files, excluding editor scratch/temp files
rsync -av \
    --exclude=".*" \
    --exclude="*.bak" \
    --exclude="*~" \
    --exclude="*.swp" \
    --exclude="*.log" \
    "$PLUGIN_SOURCE/" "$STAGE_DIR/sudokuplus.koplugin/"

# Ensure all .po in stage are compiled to .mo in stage
MSGFMT_BIN="$(which msgfmt || true)"
if [[ -n "$MSGFMT_BIN" ]]; then
    for po in "$STAGE_DIR"/sudokuplus.koplugin/l10n/*/*.po "$STAGE_DIR"/sudokuplus.koplugin/l10n/*.po; do
        [[ -f "$po" ]] || continue
        mo="${po%.po}.mo"
        "$MSGFMT_BIN" -o "$mo" "$po"
    done
fi

# Clean any OS metadata
find "$STAGE_DIR" -name ".DS_Store" -delete 2>/dev/null || true

# Create zip archive
(cd "$STAGE_DIR" && zip -r -9 "$ZIP_OUTPUT" sudokuplus.koplugin)

# Clean staging directory
rm -rf "$STAGE_DIR"

printf "\n==> Release package created: %s\n" "$ZIP_OUTPUT"
if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$ZIP_OUTPUT"
elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$ZIP_OUTPUT"
fi
