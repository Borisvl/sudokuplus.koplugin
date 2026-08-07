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
PLUGIN_SOURCE="$(pwd)/sudoku.koplugin"
KOREADER_PLUGINS="$(pwd)/$KOREADER/plugins"

link_plugin() {
    local plugin_root="$1"
    local plugin_link="$plugin_root/sudoku.koplugin"
    if [[ -e "$plugin_link" && ! -L "$plugin_link" ]]; then
        printf 'refusing to replace non-symlink %s\n' "$plugin_link" >&2
        return 1
    fi
    ln -sfn "$PLUGIN_SOURCE" "$plugin_link"
}

case "${1:-}" in
    lint)
        luacheck sudoku.koplugin/ tests/ tools/
        stylua --check sudoku.koplugin/ tests/ tools/
        exit 0
        ;;
    fmt)
        stylua sudoku.koplugin/ tests/ tools/
        exit 0
        ;;
esac

# Symlink our specs into the koreader test tree.
for spec in tests/unit/*_spec.lua; do
    [[ -e "$spec" ]] || continue
    ln -sfn "$(pwd)/$spec" "$KOREADER/spec/unit/$(basename "$spec")"
done

# Keep the checkout plugin link and every existing build directory pointed at
# the working tree. This avoids stale links when multiple build configurations
# exist and makes the test/emulator source unambiguous.
link_plugin "$KOREADER_PLUGINS"
for build_dir in "$KOREADER"/base/build/*/; do
    [[ -d "$build_dir" ]] || continue

    build_plugins="$build_dir/plugins"
    if [[ -L "$build_plugins" || ! -e "$build_plugins" ]]; then
        ln -sfn "$KOREADER_PLUGINS" "$build_plugins"
    fi
    [[ -d "$build_plugins" ]] || continue
    link_plugin "$build_plugins"
done

cd "$KOREADER"

if [[ "${1:-}" == "test" ]]; then
    shift
    exec ./kodev test front "$@"
fi

./kodev build
exec ./kodev run -s=kobo-aura-one "$@"
