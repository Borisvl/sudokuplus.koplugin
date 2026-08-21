#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=env.sh
source "$ROOT/env.sh"

for test_script in \
    "$ROOT/tests/tooling/environment_test.sh" \
    "$ROOT/tests/tooling/module_namespace_test.sh" \
    "$ROOT/tests/tooling/spec_manifest_test.sh" \
    "$ROOT/tests/tooling/test_args_test.sh" \
    "$ROOT/tests/tooling/frontend_wrapper_test.sh" \
    "$ROOT/tests/tooling/package_release_test.sh" \
    "$ROOT/tests/tooling/release_validation_test.sh" \
    "$ROOT/tests/tooling/workflow_policy_test.sh"; do
    "$test_script"
done
