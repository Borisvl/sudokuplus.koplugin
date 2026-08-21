#!/usr/bin/env bash
# Dev helper for the Sudoku+ plugin.
#   ./dev.sh                build (incremental) and run the KOReader emulator
#   ./dev.sh test [args...] run the busted specs (defaults to sudoku specs; pass --all for full frontend suite)
#   ./dev.sh test-tooling   run manifest, isolation, package, release, and workflow contract tests
#   ./dev.sh lint           luacheck + stylua --check
#   ./dev.sh fmt            stylua (apply formatting)
#   ./dev.sh pot            extract gettext strings into sudokuplus.koplugin/l10n/sudokuplus.pot
# Specs from tests/unit/ are symlinked into the (gitignored) koreader
# checkout's spec/unit/ directory, mirroring the plugin symlink approach.
set -euo pipefail
cd "$(dirname "$0")"
source env.sh

PROJECT_ROOT="$(pwd)"
KOREADER=third_party/koreader
PLUGIN_SOURCE="$PROJECT_ROOT/sudokuplus.koplugin"
KOREADER_PLUGINS="$PROJECT_ROOT/$KOREADER/plugins"

link_plugin() {
    local plugin_root="$1"
    local plugin_link="$plugin_root/sudokuplus.koplugin"
    if [[ -e "$plugin_link" && ! -L "$plugin_link" ]]; then
        printf 'refusing to replace non-symlink %s\n' "$plugin_link" >&2
        return 1
    fi
    # Clean up old legacy link if present
    rm -f "$plugin_root/sudoku.koplugin"
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
    local dest="$volume/.adds/koreader/plugins/sudokuplus.koplugin"

    # Syntax gate: never land a file that fails to compile on the device.
    local luajit="" luajit_file candidate
    for candidate in "$KOREADER"/base/build/*/luajit; do
        if [[ -x "$candidate" ]]; then
            luajit="$candidate"
            break
        fi
    done
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
        luacheck sudokuplus.koplugin/ tests/ tools/
        stylua --check sudokuplus.koplugin/ tests/ tools/
        exit 0
        ;;
    fmt)
        stylua sudokuplus.koplugin/ tests/ tools/
        exit 0
        ;;
    pot)
        exec ./tools/extract_pot.sh
        ;;
    test-tooling)
        exec ./tests/tooling/run.sh
        ;;
    deploy)
        deploy_to_device "${@:2}"
        exit 0
        ;;
esac

if [[ "${1:-}" == "test" ]]; then
    ./tools/check_test_args.sh "${@:2}"
fi

# Prune broken spec symlinks in KOReader tree and re-link current specs.
for link in "$KOREADER"/spec/unit/sudoku_*_spec.lua; do
    [[ -L "$link" && ! -e "$link" ]] && rm -f "$link"
done
for spec in tests/unit/*_spec.lua; do
    [[ -e "$spec" ]] || continue
    ln -sfn "$PROJECT_ROOT/$spec" "$KOREADER/spec/unit/$(basename "$spec")"
done
ln -sfn \
    "$PROJECT_ROOT/tests/unit/sudoku_frontend_test_guard.lua" \
    "$KOREADER/spec/unit/sudoku_frontend_test_guard.lua"

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

check_koreader_revision() {
    local expected actual
    expected="$(<"$PROJECT_ROOT/tools/koreader-revision")"
    actual="$(git rev-parse HEAD)"
    if [[ "$actual" != "$expected" ]]; then
        printf 'KOReader checkout is %s, expected pinned revision %s\n' "$actual" "$expected" >&2
        return 1
    fi
}

run_koreader_specs() {
    local category="$1"
    shift
    local runner_args=("$@")
    local paths=()
    local path
    while IFS= read -r path; do
        paths+=("${path##*/}")
        paths[${#paths[@]}-1]="${paths[${#paths[@]}-1]%_spec.lua}"
    done < <("$PROJECT_ROOT/tools/spec_manifest.sh" list "$category")
    ./kodev test front "${runner_args[@]}" "${paths[@]}"
}

run_guarded_frontend() {
    local temp_base run_root sentinel_root sentinel_contents protected_roots data_root runner_pid="" status=0
    temp_base="${TMPDIR:-/tmp}"
    run_root="$(mktemp -d "${temp_base%/}/sudoku-frontend-tests.XXXXXX")"

    cleanup_guarded_frontend() {
        trap - EXIT INT TERM HUP
        if [[ "${SUDOKU_KEEP_TEST_HOME:-0}" == "1" ]]; then
            printf 'frontend test run retained at %s\n' "$run_root" >&2
        else
            rm -rf "$run_root"
        fi
    }
    # shellcheck disable=SC2317,SC2329 # Invoked by the signal traps below.
    interrupt_guarded_frontend() {
        local signal_status="$1"
        trap - EXIT INT TERM HUP
        if [[ -n "$runner_pid" ]] && kill -0 "$runner_pid" 2>/dev/null; then
            kill -TERM "$runner_pid" 2>/dev/null || true
            wait "$runner_pid" 2>/dev/null || true
        fi
        cleanup_guarded_frontend
        exit "$signal_status"
    }
    trap cleanup_guarded_frontend EXIT
    trap 'interrupt_guarded_frontend 130' INT
    trap 'interrupt_guarded_frontend 143' TERM
    trap 'interrupt_guarded_frontend 129' HUP
    sentinel_root="$run_root/protected-sentinel"
    mkdir -p "$sentinel_root"
    sentinel_contents='return "must survive frontend tests"'
    printf '%s' "$sentinel_contents" > "$sentinel_root/sudokuplus_save"

    protected_roots=""
    for data_root in "$PROJECT_ROOT"/third_party/koreader/koreader-emulator-*/koreader; do
        [[ -d "$data_root" ]] || continue
        protected_roots="${protected_roots:+$protected_roots:}$data_root"
    done
    if [[ -n "${KO_HOME:-}" ]]; then
        protected_roots="${protected_roots:+$protected_roots:}$KO_HOME"
    fi

    SUDOKU_TEST_RUN_ROOT="$run_root" \
    SUDOKU_PROTECTED_DATA_ROOTS="$protected_roots" \
    SUDOKU_TEST_SENTINEL_ROOT="$sentinel_root" \
        ./kodev test front -w "$PROJECT_ROOT/tools/frontend_test_wrapper.sh" "$@" &
    runner_pid=$!
    set +e
    wait "$runner_pid"
    status=$?
    set -e
    runner_pid=""

    if [[ ! -f "$sentinel_root/sudokuplus_save" ]] \
        || [[ "$(<"$sentinel_root/sudokuplus_save")" != "$sentinel_contents" ]]; then
        printf 'frontend tests modified the protected sentinel save\n' >&2
        status=1
    fi
    cleanup_guarded_frontend
    return "$status"
}

run_frontend_specs() {
    local runner_args=("$@")
    local paths=()
    local path
    while IFS= read -r path; do
        paths+=("${path##*/}")
        paths[${#paths[@]}-1]="${paths[${#paths[@]}-1]%_spec.lua}"
    done < <("$PROJECT_ROOT/tools/spec_manifest.sh" list frontend)
    run_guarded_frontend "${runner_args[@]}" "${paths[@]}"
}

run_tests() {
    local common_args=()
    local explicit_core=()
    local explicit_frontend=()
    local requested_category=""
    local has_explicit_test=0
    local run_all=0
    local output_requested=0
    local arg category path basename

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
            --core)
                if [[ -n "$requested_category" && "$requested_category" != "core" ]]; then
                    printf 'dev.sh test: --core and --frontend cannot be combined\n' >&2
                    return 1
                fi
                requested_category="core"
                shift
                ;;
            --frontend)
                if [[ -n "$requested_category" && "$requested_category" != "frontend" ]]; then
                    printf 'dev.sh test: --core and --frontend cannot be combined\n' >&2
                    return 1
                fi
                requested_category="frontend"
                shift
                ;;
            -w|--wrapper|-w?*|--wrapper=*|-g|-g?*|--gdb|--gdb=*|--busted|--busted=*|--meson|--meson=*)
                printf 'dev.sh test: the frontend isolation harness owns %s\n' "$1" >&2
                return 1
                ;;
            -o|--output)
                if [[ $# -lt 2 ]]; then
                    printf 'dev.sh test: option %s requires an argument\n' "$1" >&2
                    return 1
                fi
                output_requested=1
                common_args+=("$1" "$2")
                shift 2
                ;;
            -o?*|--output=*)
                output_requested=1
                common_args+=("$1")
                shift
                ;;
            -f|--filter|-t|--tags|-j|--jobs)
                if [[ $# -lt 2 ]]; then
                    printf 'dev.sh test: option %s requires an argument\n' "$1" >&2
                    return 1
                fi
                common_args+=("$1" "$2")
                shift 2
                ;;
            -*)
                common_args+=("$1")
                shift
                ;;
            *)
                has_explicit_test=1
                arg="$1"
                arg="${arg##*/}"
                basename="${arg%_spec.lua}"
                category=""
                while IFS=' ' read -r category path; do
                    if [[ "${path##*/}" == "${basename}_spec.lua" ]]; then
                        break
                    fi
                    category=""
                done < "$PROJECT_ROOT/tests/spec-manifest.txt"
                if [[ -z "$category" ]]; then
                    printf 'dev.sh test: %s is not in tests/spec-manifest.txt\n' "$1" >&2
                    return 1
                fi
                if [[ -n "$requested_category" && "$category" != "$requested_category" ]]; then
                    printf 'dev.sh test: %s is not a %s spec\n' "$1" "$requested_category" >&2
                    return 1
                fi
                if [[ "$category" == "core" ]]; then
                    explicit_core+=("$basename")
                else
                    explicit_frontend+=("$basename")
                fi
                shift
                ;;
        esac
    done

    if [[ "$requested_category" == "core" && ${#explicit_frontend[@]} -gt 0 ]] \
        || [[ "$requested_category" == "frontend" && ${#explicit_core[@]} -gt 0 ]]; then
        printf 'dev.sh test: explicit specs do not match the requested category\n' >&2
        return 1
    fi
    if ((output_requested)) && ((run_all == 0)) \
        && { [[ -z "$requested_category" && "$has_explicit_test" -eq 0 ]] \
            || [[ ${#explicit_core[@]} -gt 0 && ${#explicit_frontend[@]} -gt 0 ]]; }; then
        printf 'dev.sh test: --output requires one category when plugin suites run separately\n' >&2
        return 1
    fi

    "$PROJECT_ROOT/tools/spec_manifest.sh" check
    check_koreader_revision

    if ((run_all)); then
        if [[ -n "$requested_category" || "$has_explicit_test" -ne 0 ]]; then
            printf 'dev.sh test: --all cannot be combined with a category or explicit spec\n' >&2
            return 1
        fi
        run_guarded_frontend "${common_args[@]}"
        return
    fi

    if ((has_explicit_test)); then
        if [[ ${#explicit_core[@]} -gt 0 ]]; then
            ./kodev test front "${common_args[@]}" "${explicit_core[@]}"
        fi
        if [[ ${#explicit_frontend[@]} -gt 0 ]]; then
            run_guarded_frontend "${common_args[@]}" "${explicit_frontend[@]}"
            return
        fi
        return
    fi

    if [[ "$requested_category" != "frontend" ]]; then
        run_koreader_specs core "${common_args[@]}"
    fi
    if [[ "$requested_category" != "core" ]]; then
        run_frontend_specs "${common_args[@]}"
    fi
}

if [[ "${1:-}" == "test" ]]; then
    shift
    run_tests "$@"
    exit $?
fi

./kodev build
exec ./kodev run -s=kobo-aura-one "$@"
