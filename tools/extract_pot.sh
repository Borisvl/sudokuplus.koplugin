#!/usr/bin/env bash
# Extracts translatable gettext strings from sudokuplus.koplugin into sudokuplus.koplugin/l10n/sudokuplus.pot
# and compiles all .po files to .mo.
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT_DIR="sudokuplus.koplugin/l10n"
OUTPUT_FILE="$OUTPUT_DIR/sudokuplus.pot"

mkdir -p "$OUTPUT_DIR"

XGETTEXT_BIN="$(which xgettext || true)"
if [[ -z "$XGETTEXT_BIN" ]]; then
    printf "error: xgettext not found in PATH\n" >&2
    exit 1
fi

TMP_FILE="$OUTPUT_DIR/sudokuplus.pot.tmp"

find sudokuplus.koplugin -name "*.lua" -print0 | sort -z | xargs -0 "$XGETTEXT_BIN" \
    --from-code=utf-8 \
    --package-name="sudokuplus" \
    --keyword=C_:1c,2 \
    --keyword=N_:1,2 \
    --keyword=NC_:1c,2,3 \
    --keyword=_ \
    --add-comments=@translators \
    --no-wrap \
    --output="$TMP_FILE"

POT_UPDATED=0
if [[ -f "$OUTPUT_FILE" ]] && diff -I '^"POT-Creation-Date:' "$TMP_FILE" "$OUTPUT_FILE" >/dev/null 2>&1; then
    rm -f "$TMP_FILE"
    printf "POT catalog %s is already up to date (%d messages).\n" \
        "$OUTPUT_FILE" \
        "$(grep -c '^msgid ' "$OUTPUT_FILE" || true)"
else
    mv "$TMP_FILE" "$OUTPUT_FILE"
    POT_UPDATED=1
    printf "Generated %s with %d extracted messages.\n" \
        "$OUTPUT_FILE" \
        "$(grep -c '^msgid ' "$OUTPUT_FILE" || true)"
fi

MSGMERGE_BIN="$(which msgmerge || true)"
MSGFMT_BIN="$(which msgfmt || true)"

for po in "$OUTPUT_DIR"/*/*.po "$OUTPUT_DIR"/*.po; do
    [[ -f "$po" ]] || continue

    if [[ "$POT_UPDATED" -eq 1 && -n "$MSGMERGE_BIN" ]]; then
        "$MSGMERGE_BIN" -q --backup=none --no-wrap --update "$po" "$OUTPUT_FILE"
        printf "Merged %s with latest POT.\n" "$po"
    fi

    if [[ -z "$MSGFMT_BIN" ]]; then
        printf "error: msgfmt not found in PATH; cannot compile %s\n" "$po" >&2
        exit 1
    fi

    mo="${po%.po}.mo"
    "$MSGFMT_BIN" -o "$mo" "$po"
    printf "Compiled %s -> %s\n" "$po" "$mo"
done
