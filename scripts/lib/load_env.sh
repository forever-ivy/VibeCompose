#!/usr/bin/env bash

# Parse repository-owned key/value files without executing their contents.
# Values intentionally use a narrow character set because these files only
# carry product identifiers and version numbers.
load_env_file() {
  local file="$1"
  shift
  local allowed_keys=" $* "
  local seen_keys="|"
  local line=""
  local line_number=0
  local key=""
  local value=""

  if [[ ! -f "$file" ]]; then
    echo "Missing environment data file: $file" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"

    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    if [[ ! "$line" =~ ^([A-Z][A-Z0-9_]*)=([A-Za-z0-9._/@:+-]+)$ ]]; then
      echo "Unsafe or malformed entry in $file at line $line_number" >&2
      return 1
    fi

    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

    case "$allowed_keys" in
      *" $key "*)
        ;;
      *)
        echo "Unexpected key $key in $file at line $line_number" >&2
        return 1
        ;;
    esac

    case "$seen_keys" in
      *"|$key|"*)
        echo "Duplicate key $key in $file at line $line_number" >&2
        return 1
        ;;
    esac

    seen_keys="${seen_keys}${key}|"
    printf -v "$key" '%s' "$value"
  done <"$file"
}

load_product_env() {
  load_env_file \
    "$1" \
    OPENWHISPER_APP_NAME \
    OPENWHISPER_BUNDLE_ID \
    OPENWHISPER_REPOSITORY \
    OPENWHISPER_MIN_MACOS
}

load_version_env() {
  load_env_file \
    "$1" \
    OPENWHISPER_VERSION \
    OPENWHISPER_BUILD
}
