#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

ARCH="${VIBEWHISPER_RELEASE_ARCHITECTURE:-$(uname -m)}"
ZIP_PATH="$ROOT/dist/${VIBEWHISPER_APP_NAME}-${VIBEWHISPER_VERSION}-macos-${ARCH}.zip"
DMG_PATH="$ROOT/dist/${VIBEWHISPER_APP_NAME}-${VIBEWHISPER_VERSION}-macos-${ARCH}.dmg"
OUTPUT_PATH="${VIBEWHISPER_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
DEFAULT_RELEASE_BASE_URL="https://github.com/${VIBEWHISPER_REPOSITORY}/releases/download/v${VIBEWHISPER_VERSION}"
RELEASE_BASE_URL="${VIBEWHISPER_RELEASE_BASE_URL:-$DEFAULT_RELEASE_BASE_URL}"
RELEASE_BASE_URL="${RELEASE_BASE_URL%/}"

if [[ "${VIBEWHISPER_REQUIRE_DEVELOPER_ID:-0}" == "1" \
  && -z "${VIBEWHISPER_RELEASE_BASE_URL:-}" ]]; then
  echo "Signed release metadata requires VIBEWHISPER_RELEASE_BASE_URL pointing to a public HTTPS artifact host." >&2
  exit 1
fi
[[ "$RELEASE_BASE_URL" == https://* \
  && "$RELEASE_BASE_URL" != *"@"* \
  && "$RELEASE_BASE_URL" != *"?"* \
  && "$RELEASE_BASE_URL" != *"#"* \
  && "$RELEASE_BASE_URL" != *[[:space:]\<\>\"\'\\]* ]] || {
  echo "VIBEWHISPER_RELEASE_BASE_URL must be a credential-free HTTPS directory URL without query or fragment." >&2
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
  --app-name "$VIBEWHISPER_APP_NAME"
  --bundle-id "$VIBEWHISPER_BUNDLE_ID"
  --repository "$VIBEWHISPER_REPOSITORY"
  --minimum-macos "$VIBEWHISPER_MIN_MACOS"
  --version "$VIBEWHISPER_VERSION"
  --build "$VIBEWHISPER_BUILD"
  --architecture "$ARCH"
  --zip "$ZIP_PATH"
  --dmg "$DMG_PATH"
  --zip-url "$RELEASE_BASE_URL/$(basename "$ZIP_PATH")"
  --dmg-url "$RELEASE_BASE_URL/$(basename "$DMG_PATH")"
)

if [[ -n "${VIBEWHISPER_RELEASE_GENERATED_AT:-}" ]]; then
  ARGS+=(--generated-at "$VIBEWHISPER_RELEASE_GENERATED_AT")
fi

swift "$ROOT/scripts/generate_release_metadata.swift" "${ARGS[@]}"
