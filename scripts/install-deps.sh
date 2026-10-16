#!/usr/bin/env bash
# Install the build tools for one target; the per-platform part is platform_install in
# scripts/platforms/<toolchain>.sh (TARGET_TOOLCHAIN, default: the platform).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

require_env TARGET_PLATFORM
require_env TARGET_ARCH

# Export a variable to later workflow steps (and this shell).
export_env() {
  export "$1=$2"
  [[ -z "${GITHUB_ENV:-}" ]] || echo "$1=$2" >>"$GITHUB_ENV"
}

install_python_build_tools() {
  # meson and ninja from PyPI are newer than most distribution packages.
  if command -v pipx >/dev/null 2>&1; then
    pipx install --force meson
    pipx install --force ninja
  else
    python3 -m pip install --quiet --user --upgrade meson ninja
  fi
  [[ -z "${GITHUB_PATH:-}" ]] || echo "$HOME/.local/bin" >>"$GITHUB_PATH"
  export PATH="$HOME/.local/bin:$PATH"
}

platform_file="$script_dir/platforms/${TARGET_TOOLCHAIN:-$TARGET_PLATFORM}.sh"
[[ -f "$platform_file" ]] || fail "Unsupported target platform: $TARGET_PLATFORM"
source "$platform_file"
platform_install
