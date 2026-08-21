# shellcheck shell=bash
# Source this file in your shell or in dev.sh:
#   source "$(dirname "$0")/env.sh"
if command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix)"
    export PATH="$BREW_PREFIX/opt/findutils/libexec/gnubin:$BREW_PREFIX/opt/gnu-getopt/bin:$BREW_PREFIX/opt/make/libexec/gnubin:$BREW_PREFIX/opt/util-linux/bin:${PATH}"
    unset BREW_PREFIX
fi
