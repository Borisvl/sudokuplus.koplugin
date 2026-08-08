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

deploy_to_device() {
    local volume="${KOBO_VOLUME:-}"
    local dry_run=0
    local no_eject=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --volume)
                volume="${2:?--volume requires a path}"
                shift 2
                ;;
            --volume=*)
                volume="${1#*=}"
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --no-eject)
                no_eject=1
                shift
                ;;
            *)
                printf 'unknown deploy option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    local candidates=()
    if [[ -n "$volume" ]]; then
        candidates=("$volume")
    else
        local v
        for v in /Volumes/*; do
            [[ -d "$v/.adds/koreader/plugins" ]] && candidates+=("$v")
        done
    fi
    if [[ ${#candidates[@]} -eq 0 ]]; then
        printf 'no KOReader volume found; plug in the Kobo and retry\n' >&2
        printf '  (or pass --volume <path>)\n' >&2
        return 1
    fi
    if [[ ${#candidates[@]} -gt 1 ]]; then
        printf 'multiple volumes contain KOReader:\n' >&2
        printf '  %s\n' "${candidates[@]}" >&2
        printf 'pass --volume <path>\n' >&2
        return 1
    fi
    volume="${candidates[0]}"
    local dest="$volume/.adds/koreader/plugins/sudoku.koplugin"

    # Syntax gate: never land a file that fails to compile on the device.
    local luajit luajit_file
    luajit="$(ls "$KOREADER/base/build"/*/luajit 2>/dev/null | head -1 || true)"
    if [[ -n "$luajit" ]]; then
        while IFS= read -r -d '' luajit_file; do
            if ! KOBO_LUAFILE="$luajit_file" "$luajit" -e 'local f, err = loadfile(os.getenv("KOBO_LUAFILE")); if not f then io.stderr:write(err .. "\n"); os.exit(1) end'; then
                printf 'syntax error in %s\n' "$luajit_file" >&2
                return 1
            fi
        done < <(find "$PLUGIN_SOURCE" -name '*.lua' -print0)
    else
        printf 'warning: checkout luajit not found, skipping syntax gate\n' >&2
    fi

    local rsync_args=(-rltDc --delete --no-perms --no-owner --no-group)
    ((dry_run)) && rsync_args+=(--dry-run)
    rsync "${rsync_args[@]}" "$PLUGIN_SOURCE/" "$dest/"

    if ((dry_run)); then
        printf 'dry run only; nothing was changed\n'
        return 0
    fi

    if ((no_eject)); then
        printf 'synced to %s\n' "$dest"
        printf 'eject the volume (diskutil eject %s), unplug, restart KOReader\n' "$volume"
        return 0
    fi

    if diskutil eject "$volume"; then
        printf 'synced and ejected %s\n' "$volume"
        printf 'unplug the Kobo and restart KOReader\n'
    else
        printf 'sync done, but ejecting %s failed\n' "$volume" >&2
        printf 'eject manually (diskutil eject %s) before unplugging\n' "$volume" >&2
        return 1
    fi
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
    deploy)
        deploy_to_device "${@:2}"
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
