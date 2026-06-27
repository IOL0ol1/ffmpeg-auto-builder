#!/usr/bin/env bash
set -euo pipefail

readonly SAFE_TOKEN_PATTERN='^[-+./:=,@%A-Za-z0-9_]+$'

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

normalize_repository_url() {
  local raw="$1"
  local cleaned="${raw%.git}"

  if [[ "$cleaned" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
    printf 'https://github.com/%s/%s.git\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$cleaned" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]]; then
    printf 'https://github.com/%s/%s.git\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  fail "Only GitHub repository URLs are supported: ${raw}"
}

build_authenticated_repository_url() {
  local repository_url="$1"
  local token="$2"
  local encoded_token
  encoded_token="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$token")"
  printf '%s\n' "${repository_url/https:\/\//https:\/\/x-access-token:${encoded_token}@}"
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
