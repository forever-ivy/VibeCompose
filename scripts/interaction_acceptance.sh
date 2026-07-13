#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"

usage() {
  cat >&2 <<USAGE
Usage:
  $0 [--install] settings [account|dictation|ai-polish|paste|privacy|advanced]
  $0 [--install] onboarding [welcome|connect|microphone|practice]
  $0 [--install] history
  $0 [--install] terminology
  $0 [--install] quick-add
  $0 --restore
USAGE
  exit 64
}

wait_for_exit() {
  local attempt
  for attempt in {1..50}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_running() {
  local attempt
  for attempt in {1..50}; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

if [[ "${1:-}" == "--restore" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  wait_for_exit
  if [[ ! -x "$APP_BINARY" ]]; then
    echo "Missing installed app binary at $APP_BINARY" >&2
    exit 1
  fi
  /usr/bin/open "$APP_DIR"
  wait_for_running
  echo "Normal installed OpenWhisper restored: $APP_DIR"
  exit 0
fi

INSTALL_FIRST=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL_FIRST=1
  shift
fi

SURFACE="${1:-}"
DETAIL="${2:-}"
[[ -n "$SURFACE" ]] || usage
[[ $# -le 2 ]] || usage

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh"
  "$ROOT/scripts/install_app.sh"
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing installed app binary at $APP_BINARY" >&2
  exit 1
fi

ARGS=("--interaction-acceptance")
case "$SURFACE" in
  settings)
    DETAIL="${DETAIL:-account}"
    case "$DETAIL" in
      account|dictation|ai-polish|paste|privacy|advanced) ;;
      *) usage ;;
    esac
    ARGS+=("--open-settings" "--settings-pane" "$DETAIL")
    ;;
  onboarding)
    DETAIL="${DETAIL:-welcome}"
    case "$DETAIL" in
      welcome|connect|microphone|practice) ;;
      *) usage ;;
    esac
    ARGS+=("--open-onboarding" "--onboarding-step" "$DETAIL")
    ;;
  history)
    [[ -z "$DETAIL" ]] || usage
    ARGS+=("--open-history")
    ;;
  terminology)
    [[ -z "$DETAIL" ]] || usage
    ARGS+=("--open-terminology")
    ;;
  quick-add)
    [[ -z "$DETAIL" ]] || usage
    ARGS+=("--open-quick-add")
    ;;
  *)
    usage
    ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
wait_for_exit
/usr/bin/open -n "$APP_DIR" --args "${ARGS[@]}"
wait_for_running

echo "Private installed-app interaction surface launched: $SURFACE${DETAIL:+/$DETAIL}"
echo "Use official Computer Use for keyboard, focus, and activation acceptance."
echo "Run '$0 --restore' when acceptance is complete."
