#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

PHASE="${1:-}"
case "$PHASE" in
  prepare|finalize) ;;
  *)
    echo "Usage: $0 prepare|finalize" >&2
    exit 64
    ;;
esac

export OPENWHISPER_REQUIRE_DEVELOPER_ID=1
export OPENWHISPER_NOTARIZE=1
export OPENWHISPER_PRO_PREVIEW_ENABLED=0
export OPENWHISPER_INSTALL_REQUIRE_GATEKEEPER=1

CASK_PATH="${OPENWHISPER_CASK_PATH:-$ROOT/dist/openwhisper.rb}"
export OPENWHISPER_CASK_PATH="$CASK_PATH"

require_environment() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required for a commercial release." >&2
    exit 1
  fi
}

for name in \
  OPENWHISPER_TEAM_ID \
  OPENWHISPER_RELEASE_BASE_URL \
  OPENWHISPER_SPARKLE_FEED_URL \
  OPENWHISPER_SPARKLE_PUBLIC_ED_KEY \
  OPENWHISPER_CAPABILITY_POLICY_URL \
  OPENWHISPER_CAPABILITY_PUBLIC_ED_KEY \
  OPENWHISPER_LICENSE_PUBLIC_ED_KEY; do
  require_environment "$name"
done

READINESS_DIRECTORY="$ROOT/dist/productization-readiness"
mkdir -p "$READINESS_DIRECTORY"

if [[ "$PHASE" == "prepare" ]]; then
  for name in \
    OPENWHISPER_CODESIGN_IDENTITY \
    OPENWHISPER_NOTARY_PROFILE \
    OPENWHISPER_SPARKLE_PRIVATE_KEY_FILE \
    OPENWHISPER_CAPABILITY_PRIVATE_KEY_FILE \
    OPENWHISPER_CAPABILITY_POLICY_REVISION \
    OPENWHISPER_CAPABILITY_POLICY_EXPIRES_AT; do
    require_environment "$name"
  done

  python3 "$ROOT/scripts/verify_productization_readiness.py" \
    --stage commercial \
    --phase prebuild \
    --output "$READINESS_DIRECTORY/prebuild.json"

  "$ROOT/scripts/check.sh"
  "$ROOT/scripts/package_app.sh"
  "$ROOT/scripts/generate_sparkle_appcast.sh"

  OPENWHISPER_CAPABILITY_PRIVATE_KEY_FILE="$OPENWHISPER_CAPABILITY_PRIVATE_KEY_FILE" \
    "$ROOT/scripts/generate_provider_capability_policy.swift" \
      --revision "$OPENWHISPER_CAPABILITY_POLICY_REVISION" \
      --incident-id "${OPENWHISPER_CAPABILITY_POLICY_INCIDENT_ID:-OW-RELEASE-${OPENWHISPER_BUILD}}" \
      --expires-at "$OPENWHISPER_CAPABILITY_POLICY_EXPIRES_AT" \
      --enable-all \
      --minimum-build "$OPENWHISPER_BUILD" \
      --output "$ROOT/dist/provider-capabilities.json"

  OPENWHISPER_CASK_OUTPUT_PATH="$CASK_PATH" \
    "$ROOT/scripts/update_homebrew_cask.sh"
  "$ROOT/scripts/verify_release_gate.sh"
  "$ROOT/scripts/install_app.sh"

  if [[ "${OPENWHISPER_RUN_SCRIPTED_ACCEPTANCE:-0}" == "1" ]]; then
    "$ROOT/scripts/visual_acceptance.sh"
    "$ROOT/scripts/product_surface_acceptance.sh"
    "$ROOT/scripts/accessibility_acceptance.sh"
    "$ROOT/scripts/accessibility_visual_acceptance.sh"
    "$ROOT/scripts/paste_acceptance.sh"
    "$ROOT/scripts/permission_surface_acceptance.sh"
  fi

  cat <<EOF
Commercial candidate prepared and installed at /Applications/$OPENWHISPER_APP_NAME.app.

Before finalize:
1. Publish the ZIP, DMG, appcast, and provider policy to their configured public HTTPS URLs.
2. Complete release/installed-acceptance.json with real Developer ID, notarization,
   clean-TCC, keyboard, VoiceOver, compatibility, update, rollback, and uninstall evidence.
3. Complete approved operator, brand-clearance, and beta-metrics files.
4. Create tag v$OPENWHISPER_VERSION on the exact release commit.
5. Run: $0 finalize
EOF
  exit 0
fi

python3 "$ROOT/scripts/verify_productization_readiness.py" \
  --stage commercial \
  --phase final \
  --output "$READINESS_DIRECTORY/final.json"
"$ROOT/scripts/verify_release_gate.sh"
"$ROOT/scripts/verify_remote_release_assets.sh"

EVIDENCE_DIRECTORY="$ROOT/dist/release-evidence"
rm -rf "$EVIDENCE_DIRECTORY"
mkdir -p "$EVIDENCE_DIRECTORY"
for path in \
  "$ROOT/dist/release-manifest.json" \
  "$ROOT/dist/SHA256SUMS" \
  "$ROOT/dist/appcast.xml" \
  "$ROOT/dist/provider-capabilities.json" \
  "$CASK_PATH" \
  "$READINESS_DIRECTORY/final.json" \
  "$ROOT/docs/releases/v${OPENWHISPER_VERSION}.md" \
  "$ROOT/docs/releases/v${OPENWHISPER_VERSION}.zh-CN.md" \
  "$ROOT/release/commercial-operator.json" \
  "$ROOT/release/brand-clearance.json" \
  "$ROOT/release/beta-metrics.json" \
  "$ROOT/release/installed-acceptance.json"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "Missing final release evidence: $path" >&2
    exit 1
  }
  /usr/bin/ditto "$path" "$EVIDENCE_DIRECTORY/$(basename "$path")"
done

(
  cd "$EVIDENCE_DIRECTORY"
  /usr/bin/shasum -a 256 ./* >EVIDENCE-SHA256SUMS
)
/usr/bin/ditto \
  -c \
  -k \
  --sequesterRsrc \
  "$EVIDENCE_DIRECTORY" \
  "$ROOT/dist/${OPENWHISPER_APP_NAME}-${OPENWHISPER_VERSION}-release-evidence.zip"

echo "OpenWhisper commercial release finalization passed."
echo "Evidence: $ROOT/dist/${OPENWHISPER_APP_NAME}-${OPENWHISPER_VERSION}-release-evidence.zip"
