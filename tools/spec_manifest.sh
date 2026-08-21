#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_MANIFEST="$ROOT/tests/spec-manifest.txt"

die() {
    printf 'spec manifest: %s\n' "$*" >&2
    exit 1
}

absolute_path() {
    local path="$1"
    local directory
    if [[ "$path" != /* ]]; then
        path="$ROOT/$path"
    fi
    directory="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$directory" "$(basename "$path")"
}

first_code_match() {
    local pattern="$1"
    local file="$2"
    local number text
    while IFS=: read -r number text; do
        [[ "$text" =~ ^[[:space:]]*-- ]] && continue
        printf '%s\n' "$number"
        return
    done < <(grep -n -E "$pattern" "$file" || true)
}

check_manifest() {
    local manifest="${1:-$DEFAULT_MANIFEST}"
    local spec_dir="${2:-$ROOT/tests/unit}"
    local tmp
    local normalized
    local discovered
    local sorted
    local line=0
    local category path extra absolute
    local guard_line install_line runtime_line

    [[ -f "$manifest" ]] || die "missing $manifest"
    [[ -d "$spec_dir" ]] || die "missing spec directory $spec_dir"

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/sudoku-spec-check.XXXXXX")"
    CHECK_TEMP_DIR="$tmp"
    trap 'rm -rf "$CHECK_TEMP_DIR"' EXIT
    normalized="$tmp/manifest-paths"
    discovered="$tmp/discovered-paths"
    sorted="$tmp/sorted-manifest"
    : > "$normalized"

    while IFS=' ' read -r category path extra; do
        line=$((line + 1))
        [[ -n "$category" && -n "$path" && -z "${extra:-}" ]] \
            || die "$manifest:$line must contain exactly a category and path"
        [[ "$category" == "core" || "$category" == "frontend" ]] \
            || die "$manifest:$line has invalid category $category"
        [[ "$path" == *_spec.lua ]] || die "$manifest:$line is not a spec path"
        absolute="$(absolute_path "$path")" || die "$manifest:$line has an invalid parent directory"
        [[ -f "$absolute" ]] || die "$manifest:$line points to missing file $path"
        if [[ "$category" == "frontend" ]]; then
            guard_line="$(first_code_match "require[[:space:]]*(\\([[:space:]]*)?['\"]sudoku_frontend_test_guard['\"]" "$absolute")"
            install_line="$(first_code_match '(test_guard|guard)[[:space:]]*\.[[:space:]]*install[[:space:]]*\(' "$absolute")"
            runtime_line="$(first_code_match "require[[:space:]]*(\\([[:space:]]*)?['\"](commonrequire|datastorage|gettext|ffi/|ui/|device)" "$absolute")"
            [[ -n "$guard_line" && -n "$install_line" ]] \
                || die "$path must install sudoku_frontend_test_guard"
            if [[ -n "$runtime_line" && "$install_line" -ge "$runtime_line" ]]; then
                die "$path must install sudoku_frontend_test_guard before KOReader modules"
            fi
        elif [[ -n "$(first_code_match "require[[:space:]]*(\\([[:space:]]*)?['\"](commonrequire|datastorage|gettext|ffi/|ui/|device)" "$absolute")" ]]; then
            die "$path is a core spec but directly requires a KOReader module"
        fi
        printf '%s\n' "$absolute" >> "$normalized"
    done < "$manifest"

    [[ "$line" -gt 0 ]] || die "$manifest is empty"
    if [[ "$(sort "$normalized" | uniq -d | wc -l | tr -d ' ')" != "0" ]]; then
        die "$manifest contains duplicate specs"
    fi

    LC_ALL=C sort "$manifest" > "$sorted"
    cmp -s "$manifest" "$sorted" || die "$manifest must be sorted by category and path"

    : > "$discovered"
    for path in "$spec_dir"/*_spec.lua; do
        [[ -e "$path" ]] || continue
        absolute="$(absolute_path "$path")" || die "cannot normalize $path"
        printf '%s\n' "$absolute" >> "$discovered"
    done
    LC_ALL=C sort -u -o "$normalized" "$normalized"
    LC_ALL=C sort -u -o "$discovered" "$discovered"
    if ! cmp -s "$normalized" "$discovered"; then
        printf 'spec manifest: classified and discovered specs differ:\n' >&2
        diff -u "$normalized" "$discovered" >&2 || true
        exit 1
    fi
}

list_specs() {
    local category="${1:?category is required}"
    local manifest="${2:-$DEFAULT_MANIFEST}"
    [[ "$category" == "core" || "$category" == "frontend" ]] || die "invalid category $category"
    [[ -f "$manifest" ]] || die "missing $manifest"
    while IFS=' ' read -r entry_category path extra; do
        [[ -n "$entry_category" && -n "$path" && -z "${extra:-}" ]] || die "malformed $manifest"
        if [[ "$entry_category" == "$category" ]]; then
            printf '%s\n' "$path"
        fi
    done < "$manifest"
}

case "${1:-}" in
    check)
        shift
        check_manifest "$@"
        ;;
    list)
        shift
        list_specs "$@"
        ;;
    *)
        die "usage: $0 check [manifest [spec-dir]] | list <core|frontend> [manifest]"
        ;;
esac
