#!/usr/bin/env bash
# Dev helper for the Sudoku plugin.
#   ./dev.sh                build (incremental) and run the KOReader emulator
#   ./dev.sh test [args...] run the busted specs (defaults to sudoku specs; pass --all for full frontend suite)
#   ./dev.sh lint           luacheck + stylua --check
#   ./dev.sh fmt            stylua (apply formatting)
#   ./dev.sh pot            extract gettext strings into sudoku.koplugin/l10n/sudoku.pot
# Specs from tests/unit/ are symlinked into the (gitignored) koreader
# checkout's spec/unit/ directory, mirroring the plugin symlink approach.
set -euo pipefail
cd "$(dirname "$0")"
source env.sh

PROJECT_ROOT="$(pwd)"
KOREADER=third_party/koreader
PLUGIN_SOURCE="$PROJECT_ROOT/sudoku.koplugin"
KOREADER_PLUGINS="$PROJECT_ROOT/$KOREADER/plugins"

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
    pot)
        exec ./tools/extract_pot.sh
        ;;
    deploy)
        deploy_to_device "${@:2}"
        exit 0
        ;;
esac

# Prune broken spec symlinks in KOReader tree and re-link current specs.
for link in "$KOREADER"/spec/unit/sudoku_*_spec.lua; do
    [[ -L "$link" && ! -e "$link" ]] && rm -f "$link"
done
for spec in tests/unit/*_spec.lua; do
    [[ -e "$spec" ]] || continue
    ln -sfn "$PROJECT_ROOT/$spec" "$KOREADER/spec/unit/$(basename "$spec")"
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

run_tests() {
    local test_args=()
    local has_explicit_test=0
    local run_all=0

    # Note: Value-flag list mirrors RUNTESTS_GETOPT_SHORT/LONG in
    # third_party/koreader/base/test-runner/runtests. Flags with optional
    # arguments (--busted::, --meson::) must use '=' syntax (e.g. --busted=...).
    # Positional test names assume the default Meson runner.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                run_all=1
                shift
                ;;
            -f|--filter|-t|--tags|-j|--jobs|-o|--output|-w|--wrapper)
                if [[ $# -lt 2 ]]; then
                    printf 'dev.sh test: option %s requires an argument\n' "$1" >&2
                    return 1
                fi
                test_args+=("$1" "$2")
                shift 2
                ;;
            -*)
                test_args+=("$1")
                shift
                ;;
            *)
                has_explicit_test=1
                # Normalize file paths or spec suffixes (e.g. tests/unit/foo_spec.lua -> foo)
                local arg="$1"
                arg="${arg##*/}"
                arg="${arg%_spec.lua}"
                test_args+=("$arg")
                shift
                ;;
        esac
    done

    # If no explicit test targets are given and --all is not set, default to all
    # plugin specs. Note: passing -f/-t without explicit test names will run
    # each of the 46 plugin spec targets filtered by busted.
    if (( !run_all && !has_explicit_test )); then
        local spec
        for spec in "$PROJECT_ROOT"/tests/unit/*_spec.lua; do
            [[ -e "$spec" ]] || continue
            test_args+=("$(basename "$spec" _spec.lua)")
        done
    fi

    exec ./kodev test front "${test_args[@]}"
}

if [[ "${1:-}" == "test" ]]; then
    shift
    run_tests "$@"
fi

./kodev build
exec ./kodev run -s=kobo-aura-one "$@"
