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

cd "$KOREADER"

if [[ "${1:-}" == "test" ]]; then
    shift
    exec ./kodev test front "$@"
fi

./kodev build
exec ./kodev run -s=kobo-aura-one "$@"
