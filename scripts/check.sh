#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift build --package-path "$ROOT"
swift test --package-path "$ROOT"
swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT"
node "$ROOT/scripts/check_landing_page.mjs"
bash "$ROOT/scripts/check_packaged_app.sh"
