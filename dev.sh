#!/usr/bin/env bash
# Dev helper for the Sudoku plugin.
#   ./dev.sh                build (incremental) and run the KOReader emulator
#   ./dev.sh test [args...] run the busted specs (args passed to `kodev test front`)
# Specs from tests/unit/ are symlinked into the (gitignored) koreader
# checkout's spec/unit/ directory, mirroring the plugin symlink approach.
set -euo pipefail
cd "$(dirname "$0")"
source env.sh

KOREADER=third_party/koreader

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
