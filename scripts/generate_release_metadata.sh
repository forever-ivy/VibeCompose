#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

ARCH="${OPENWHISPER_RELEASE_ARCHITECTURE:-$(uname -m)}"
ZIP_PATH="$ROOT/dist/${OPENWHISPER_APP_NAME}-${OPENWHISPER_VERSION}-macos-${ARCH}.zip"
DMG_PATH="$ROOT/dist/${OPENWHISPER_APP_NAME}-${OPENWHISPER_VERSION}-macos-${ARCH}.dmg"
OUTPUT_PATH="${OPENWHISPER_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
DEFAULT_RELEASE_BASE_URL="https://github.com/${OPENWHISPER_REPOSITORY}/releases/download/v${OPENWHISPER_VERSION}"
RELEASE_BASE_URL="${OPENWHISPER_RELEASE_BASE_URL:-$DEFAULT_RELEASE_BASE_URL}"
RELEASE_BASE_URL="${RELEASE_BASE_URL%/}"

if [[ "${OPENWHISPER_REQUIRE_DEVELOPER_ID:-0}" == "1" \
  && -z "${OPENWHISPER_RELEASE_BASE_URL:-}" ]]; then
  echo "Signed release metadata requires OPENWHISPER_RELEASE_BASE_URL pointing to a public HTTPS artifact host." >&2
  exit 1
fi
[[ "$RELEASE_BASE_URL" == https://* \
  && "$RELEASE_BASE_URL" != *"@"* \
  && "$RELEASE_BASE_URL" != *"?"* \
  && "$RELEASE_BASE_URL" != *"#"* \
  && "$RELEASE_BASE_URL" != *[[:space:]\<\>\"\'\\]* ]] || {
  echo "OPENWHISPER_RELEASE_BASE_URL must be a credential-free HTTPS directory URL without query or fragment." >&2
  exit 1
}

[[ -f "$ZIP_PATH" ]] || {
  echo "Missing release ZIP: $ZIP_PATH" >&2
  exit 1
}
[[ -f "$DMG_PATH" ]] || {
  echo "Missing release DMG: $DMG_PATH" >&2
  exit 1
}

ARGS=(
  --output "$OUTPUT_PATH"
  --app-name "$OPENWHISPER_APP_NAME"
  --bundle-id "$OPENWHISPER_BUNDLE_ID"
  --repository "$OPENWHISPER_REPOSITORY"
  --minimum-macos "$OPENWHISPER_MIN_MACOS"
  --version "$OPENWHISPER_VERSION"
  --build "$OPENWHISPER_BUILD"
  --architecture "$ARCH"
  --zip "$ZIP_PATH"
  --dmg "$DMG_PATH"
  --zip-url "$RELEASE_BASE_URL/$(basename "$ZIP_PATH")"
  --dmg-url "$RELEASE_BASE_URL/$(basename "$DMG_PATH")"
)

if [[ -n "${OPENWHISPER_RELEASE_GENERATED_AT:-}" ]]; then
  ARGS+=(--generated-at "$OPENWHISPER_RELEASE_GENERATED_AT")
fi

swift "$ROOT/scripts/generate_release_metadata.swift" "${ARGS[@]}"
