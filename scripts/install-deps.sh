#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

require_env TARGET_PLATFORM
require_env TARGET_ARCH

case "$TARGET_PLATFORM" in
  linux)
    sudo apt-get update
    sudo apt-get install -y build-essential pkg-config nasm zip ccache patchelf

    # Install cross-compilation toolchain when targeting a non-native architecture
    case "$TARGET_ARCH" in
      x86)
        sudo apt-get install -y gcc-i686-linux-gnu g++-i686-linux-gnu binutils-i686-linux-gnu
        ;;
      armv7)
        sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf binutils-arm-linux-gnueabihf
        ;;
      arm64 | x86_64)
        # Native build — no extra toolchain needed
        ;;
    esac
    ;;
  macos)
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install nasm pkg-config ccache
    ;;
  windows)
    # MSYS2 packages are installed by the msys2/setup-msys2 step in the workflow.
    ;;
  *)
    fail "Unsupported target platform: $TARGET_PLATFORM"
    ;;
esac
