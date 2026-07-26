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

export VIBECOMPOSE_REQUIRE_DEVELOPER_ID=1
export VIBECOMPOSE_NOTARIZE=1
export VIBECOMPOSE_INSTALL_REQUIRE_GATEKEEPER=1
export VIBECOMPOSE_BUILD_CONFIGURATION=release

CASK_PATH="${VIBECOMPOSE_CASK_PATH:-$ROOT/dist/vibecompose.rb}"
export VIBECOMPOSE_CASK_PATH="$CASK_PATH"
BRAND_CLEARANCE_PATH="${VIBECOMPOSE_BRAND_CLEARANCE_PATH:-$ROOT/release/brand-clearance.json}"
INSTALLED_ACCEPTANCE_PATH="${VIBECOMPOSE_INSTALLED_ACCEPTANCE_PATH:-$ROOT/release/installed-acceptance.json}"
COMMUNITY_PILOT_SUMMARY_PATH="${VIBECOMPOSE_COMMUNITY_PILOT_SUMMARY_PATH:-$ROOT/release/community-pilot-summary.json}"
BETA_METRICS_PATH="${VIBECOMPOSE_BETA_METRICS_PATH:-$ROOT/release/beta-metrics.json}"
PUBLIC_CONTACT_PATH="${VIBECOMPOSE_PUBLIC_CONTACT_PATH:-$ROOT/release/public-contact.json}"
CANDIDATE_READINESS_REPORT="$ROOT/dist/release-candidate-readiness.json"
PUBLIC_READINESS_REPORT="$ROOT/dist/public-release-readiness.json"

require_environment() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required for a signed release." >&2
    exit 1
  fi
}

for name in \
  VIBECOMPOSE_TEAM_ID \
  VIBECOMPOSE_RELEASE_BASE_URL \
  VIBECOMPOSE_SPARKLE_FEED_URL \
  VIBECOMPOSE_SPARKLE_PUBLIC_ED_KEY \
  VIBECOMPOSE_CAPABILITY_POLICY_URL \
  VIBECOMPOSE_CAPABILITY_PUBLIC_ED_KEY; do
  require_environment "$name"
done

if [[ "$PHASE" == "prepare" ]]; then
  for name in \
    VIBECOMPOSE_CODESIGN_IDENTITY \
    VIBECOMPOSE_NOTARY_PROFILE \
    VIBECOMPOSE_SPARKLE_PRIVATE_KEY_FILE \
    VIBECOMPOSE_CAPABILITY_PRIVATE_KEY_FILE \
    VIBECOMPOSE_CAPABILITY_POLICY_REVISION \
    VIBECOMPOSE_CAPABILITY_POLICY_EXPIRES_AT; do
    require_environment "$name"
  done

  mkdir -p "$ROOT/dist"
  python3 "$ROOT/scripts/verify_release_readiness.py" \
    --phase candidate \
    --output "$CANDIDATE_READINESS_REPORT"
  "$ROOT/scripts/check.sh"
  "$ROOT/scripts/package_app.sh"
  "$ROOT/scripts/generate_sparkle_appcast.sh"

  VIBECOMPOSE_CAPABILITY_PRIVATE_KEY_FILE="$VIBECOMPOSE_CAPABILITY_PRIVATE_KEY_FILE" \
    "$ROOT/scripts/generate_provider_capability_policy.swift" \
      --revision "$VIBECOMPOSE_CAPABILITY_POLICY_REVISION" \
      --incident-id "${VIBECOMPOSE_CAPABILITY_POLICY_INCIDENT_ID:-OW-RELEASE-${VIBECOMPOSE_BUILD}}" \
      --expires-at "$VIBECOMPOSE_CAPABILITY_POLICY_EXPIRES_AT" \
      --enable-all \
      --minimum-build "$VIBECOMPOSE_BUILD" \
      --output "$ROOT/dist/provider-capabilities.json"

  VIBECOMPOSE_CASK_OUTPUT_PATH="$CASK_PATH" \
    "$ROOT/scripts/update_homebrew_cask.sh"
  "$ROOT/scripts/verify_release_gate.sh"
  "$ROOT/scripts/install_app.sh"

  if [[ "${VIBECOMPOSE_RUN_SCRIPTED_ACCEPTANCE:-0}" == "1" ]]; then
    "$ROOT/scripts/visual_acceptance.sh" --install
    "$ROOT/scripts/paste_acceptance.sh" --install
    "$ROOT/scripts/check_packaged_app.sh"
  fi

  cat <<EOF
Signed candidate prepared and installed at /Applications/$VIBECOMPOSE_APP_NAME.app.

Before any public upload:
1. Record real installed-app, accessibility, update, rollback, and uninstall evidence for this exact candidate.
2. Complete the four-week Community Pilot aggregate and product-owner Beta review.
3. Resolve brand clearance and create tag v$VIBECOMPOSE_VERSION on this exact release commit.
4. Run the public phase of scripts/verify_release_readiness.py; do not publish while it is blocked.

After that gate passes, publish the ZIP, DMG, appcast, and provider policy to
the configured HTTPS URLs, then run: $0 finalize
EOF
  exit 0
fi

python3 "$ROOT/scripts/verify_release_readiness.py" \
  --phase public \
  --output "$PUBLIC_READINESS_REPORT"
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
  "$ROOT/dist/notarization-app.json" \
  "$ROOT/dist/notarization-dmg.json" \
  "$CANDIDATE_READINESS_REPORT" \
  "$PUBLIC_READINESS_REPORT" \
  "$CASK_PATH" \
  "$ROOT/docs/releases/v${VIBECOMPOSE_VERSION}.md" \
  "$ROOT/docs/releases/v${VIBECOMPOSE_VERSION}.zh-CN.md"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "Missing final release evidence: $path" >&2
    exit 1
  }
  /usr/bin/ditto "$path" "$EVIDENCE_DIRECTORY/$(basename "$path")"
done

copy_release_evidence() {
  local source="$1"
  local destination_name="$2"
  [[ -f "$source" && ! -L "$source" ]] || {
    echo "Missing or unsafe public-release evidence: $source" >&2
    exit 1
  }
  /usr/bin/ditto "$source" "$EVIDENCE_DIRECTORY/$destination_name"
}

copy_release_evidence "$BRAND_CLEARANCE_PATH" brand-clearance.json
copy_release_evidence "$INSTALLED_ACCEPTANCE_PATH" installed-acceptance.json
copy_release_evidence "$COMMUNITY_PILOT_SUMMARY_PATH" community-pilot-summary.json
copy_release_evidence "$BETA_METRICS_PATH" beta-metrics.json
copy_release_evidence "$PUBLIC_CONTACT_PATH" public-contact.json

(
  cd "$EVIDENCE_DIRECTORY"
  /usr/bin/shasum -a 256 ./* >EVIDENCE-SHA256SUMS
)
/usr/bin/ditto \
  -c \
  -k \
  --sequesterRsrc \
  "$EVIDENCE_DIRECTORY" \
  "$ROOT/dist/${VIBECOMPOSE_APP_NAME}-${VIBECOMPOSE_VERSION}-release-evidence.zip"

echo "VibeCompose signed release finalization passed."
echo "Evidence: $ROOT/dist/${VIBECOMPOSE_APP_NAME}-${VIBECOMPOSE_VERSION}-release-evidence.zip"
