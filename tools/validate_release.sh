#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

die() {
    printf 'release validation: %s\n' "$*" >&2
    exit 1
}

validate_tag() {
    [[ "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
        || die "tag must match vX.Y.Z without leading zeros or suffixes"
}

case "${1:-}" in
    files)
        [[ $# == 5 ]] || die "usage: $0 files <tag> <metadata> <changelog> <notes>"
        validate_tag "$2"
        exec python3 "$ROOT/tools/validate_release.py" "$2" "$3" "$4" "$5"
        ;;
    git)
        [[ $# == 5 ]] || die "usage: $0 git <tag> <expected-sha> <main-ref> <repository>"
        tag="$2"
        expected_sha="$3"
        main_ref="$4"
        repository="$5"
        validate_tag "$tag"
        [[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]] || die "expected SHA must contain 40 lowercase hex characters"
        git -C "$repository" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null \
            || die "$tag must exist"
        tag_sha="$(git -C "$repository" rev-parse "refs/tags/$tag^{commit}")"
        head_sha="$(git -C "$repository" rev-parse HEAD)"
        [[ "$tag_sha" == "$expected_sha" ]] || die "tag commit does not match expected SHA"
        [[ "$head_sha" == "$expected_sha" ]] || die "checked-out HEAD does not match expected SHA"
        git -C "$repository" merge-base --is-ancestor "$tag_sha" "$main_ref" \
            || die "tag commit is not reachable from $main_ref"
        ;;
    *)
        die "usage: $0 files ... | git ..."
        ;;
esac
