#!/usr/bin/env bash
set -euo pipefail

readonly SAFE_TOKEN_PATTERN='^[-+./:=,@%A-Za-z0-9_]+$'
readonly RELEASE_TAG_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Missing required environment variable: ${name}"
  fi
}

# Print "owner/repo" for a GitHub repository URL (HTTPS or SSH form).
parse_repository_slug() {
  local raw="$1"
  local cleaned="${raw%/}"
  cleaned="${cleaned%.git}"

  if [[ "$cleaned" =~ ^https?://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]] \
    || [[ "$cleaned" =~ ^git@github\.com:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  fail "Only GitHub repository URLs are supported: ${raw}"
}

validate_release_tag() {
  [[ "$1" =~ $RELEASE_TAG_PATTERN ]] || fail "Unsafe release tag: $1"
}

sanitize_configure_options() {
  local raw="$1"
  local normalized
  normalized="$(printf '%s' "$raw" | tr '\r\n\t' '   ')"
  read -r -a tokens <<<"$normalized"

  [[ "${#tokens[@]}" -gt 0 ]] || fail "configure options are empty"

  SANITIZED_CONFIGURE_ARGS=()
  local token
  for token in "${tokens[@]}"; do
    [[ "$token" =~ $SAFE_TOKEN_PATTERN ]] || fail "Unsafe configure token detected: ${token}"
    # The install prefix is managed by build-ffmpeg.sh; overriding it would break packaging.
    [[ "$token" != --prefix=* ]] || fail "--prefix is managed by the build and cannot be overridden"
    SANITIZED_CONFIGURE_ARGS+=("$token")
  done
}

cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return
  fi

  sysctl -n hw.ncpu
}
