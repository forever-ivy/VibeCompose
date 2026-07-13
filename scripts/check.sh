#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift build --package-path "$ROOT"
swift test --package-path "$ROOT"
swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT"
python3 "$ROOT/scripts/verify_repository_hygiene.py"
node "$ROOT/scripts/check_landing_page.mjs"
bash "$ROOT/scripts/check_packaged_app.sh"
