#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift build --package-path "$ROOT"
SWIFT_TEST_LOG="$(mktemp -t vibecompose-swift-test.XXXXXX)"
chmod 600 "$SWIFT_TEST_LOG"
trap 'rm -f "$SWIFT_TEST_LOG"' EXIT
set +e
swift test --package-path "$ROOT" 2>&1 | tee "$SWIFT_TEST_LOG"
SWIFT_TEST_STATUS=${PIPESTATUS[0]}
set -e
python3 "$ROOT/scripts/verify_swift_test_output.py" \
  --command-status "$SWIFT_TEST_STATUS" \
  "$SWIFT_TEST_LOG"
swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT"
python3 "$ROOT/scripts/verify_repository_hygiene.py"
python3 "$ROOT/scripts/summarize_community_pilot.py" --self-test
python3 "$ROOT/scripts/verify_release_readiness.py" --self-test
node "$ROOT/scripts/check_landing_page.mjs"
bash "$ROOT/scripts/check_packaged_app.sh"
