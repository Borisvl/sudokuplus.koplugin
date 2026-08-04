#!/usr/bin/env bash
# Dev helper for the Sudoku plugin.
#   ./dev.sh                build (incremental) and run the KOReader emulator
#   ./dev.sh test [args...] run the busted specs (args passed to `kodev test front`)
#   ./dev.sh lint           luacheck + stylua --check
#   ./dev.sh fmt            stylua (apply formatting)
# Specs from tests/unit/ are symlinked into the (gitignored) koreader
# checkout's spec/unit/ directory, mirroring the plugin symlink approach.
set -euo pipefail
cd "$(dirname "$0")"
source env.sh

KOREADER=third_party/koreader

case "${1:-}" in
    lint)
        luacheck sudoku.koplugin/ tests/
        stylua --check sudoku.koplugin/ tests/
        exit 0
        ;;
    fmt)
        stylua sudoku.koplugin/ tests/
        exit 0
        ;;
esac

# Symlink our specs into the koreader test tree.
for spec in tests/unit/*_spec.lua; do
    [[ -e "$spec" ]] || continue
    ln -sfn "$(pwd)/$spec" "$KOREADER/spec/unit/$(basename "$spec")"
done

# Make the plugin requireable from the test CWD (the meson build dir):
# specs use `require("core.board")` with package.path including
# plugins/sudoku.koplugin/?.lua (same layout as the emulator bundle).
BUILD_DIR=$(ls -d "$KOREADER"/base/build/*/ 2>/dev/null | head -1 || true)
if [[ -n "$BUILD_DIR" && ! -e "$BUILD_DIR/plugins" ]]; then
    ln -sfn "$(pwd)/$KOREADER/plugins" "$BUILD_DIR/plugins"
fi

cd "$KOREADER"

if [[ "${1:-}" == "test" ]]; then
    shift
    exec ./kodev test front "$@"
fi

./kodev build
exec ./kodev run -s=kobo-aura-one "$@"
