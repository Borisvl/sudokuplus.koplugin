#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_ROOT="$ROOT/sudokuplus.koplugin"

fail() {
    printf 'module_namespace_test: %s\n' "$*" >&2
    exit 1
}

[[ -d "$PLUGIN_ROOT/sudokuplus" ]] || fail "missing private sudokuplus module directory"

double_require_pattern='require[[:space:]]*(\([[:space:]]*)?"(_meta|json|game|game_serialize|stats|storage|core\.|ui\.)'
single_require_pattern="require[[:space:]]*(\\([[:space:]]*)?'(_meta|json|game|game_serialize|stats|storage|core\\.|ui\\.)"
if grep -R -n -E --include='*.lua' "$double_require_pattern" "$PLUGIN_ROOT" \
    || grep -R -n -E --include='*.lua' "$single_require_pattern" "$PLUGIN_ROOT"; then
    fail "plugin source contains an unnamespaced private require"
fi

for source in "$PLUGIN_ROOT"/*.lua; do
    case "$(basename "$source")" in
        _meta.lua | main.lua) ;;
        *) fail "private Lua module remains at plugin root: $source" ;;
    esac
done

printf 'module_namespace_test: ok\n'
