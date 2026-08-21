#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        -w|--wrapper|-w?*|--wrapper=*|-g|-g?*|--gdb|--gdb=*|--busted|--busted=*|--meson|--meson=*)
            printf 'dev.sh test: option %s can bypass the frontend isolation harness\n' "$arg" >&2
            exit 1
            ;;
    esac
done
