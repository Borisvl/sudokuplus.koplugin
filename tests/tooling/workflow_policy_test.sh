#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CI="$ROOT/.github/workflows/ci.yml"
RELEASE="$ROOT/.github/workflows/release.yml"

fail() {
    printf 'workflow_policy_test: %s\n' "$*" >&2
    exit 1
}

if grep -Eq 'uses: [^ ]+@v[0-9]' "$CI" "$RELEASE"; then
    fail "actions must be pinned to full commit SHAs"
fi
if grep -q 'ubuntu-latest' "$CI" "$RELEASE"; then
    fail "runner version must be explicit"
fi
if grep -q 'releases/latest' "$CI" "$RELEASE"; then
    fail "tool downloads must be version- and checksum-pinned"
fi
grep -q 'workflow_call:' "$CI" || fail "CI must be reusable by release"
grep -q 'spec_manifest.sh' "$CI" || fail "CI must enforce the spec manifest"
grep -q 'test-frontend' "$CI" || fail "CI must run frontend specs"
grep -q 'validate_release.sh' "$RELEASE" || fail "release must validate tag metadata"
grep -q 'package_release.sh' "$CI" || fail "release CI gates must build the verified package"
grep -q 'verify_release_package.py' "$ROOT/tools/package_release.sh" || fail "packager must invoke the archive verifier"
grep -q 'sudokuplus.koplugin.zip.sha256' "$RELEASE" || fail "release must publish a checksum"
grep -q 'gh release edit' "$RELEASE" || fail "retagging must update the existing release"
grep -q -- '--clobber' "$RELEASE" || fail "retagging must replace existing release assets"
if grep -q 'Refuse an existing release' "$RELEASE"; then
    fail "an existing release must not block intentional retagging"
fi

printf 'workflow_policy_test: ok\n'
