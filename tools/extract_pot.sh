#!/usr/bin/env bash
# Extracts translatable gettext strings from sudoku.koplugin into sudoku.koplugin/l10n/sudoku.pot.
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT_DIR="sudoku.koplugin/l10n"
OUTPUT_FILE="$OUTPUT_DIR/sudoku.pot"

mkdir -p "$OUTPUT_DIR"

XGETTEXT_BIN="$(which xgettext || true)"
if [[ -z "$XGETTEXT_BIN" ]]; then
    printf "error: xgettext not found in PATH\n" >&2
    exit 1
fi

find sudoku.koplugin -name "*.lua" -print0 | sort -z | xargs -0 "$XGETTEXT_BIN" \
    --from-code=utf-8 \
    --package-name="sudoku" \
    --keyword=C_:1c,2 \
    --keyword=N_:1,2 \
    --keyword=NC_:1c,2,3 \
    --keyword=_ \
    --add-comments=@translators \
    --output="$OUTPUT_FILE"

printf "Generated %s with %d extracted messages.\n" \
    "$OUTPUT_FILE" \
    "$(grep -c '^msgid ' "$OUTPUT_FILE" || true)"
