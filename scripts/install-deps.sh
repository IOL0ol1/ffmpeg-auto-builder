#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

require_env TARGET_PLATFORM
require_env TARGET_ARCH

case "$TARGET_PLATFORM" in
  linux)
    sudo apt-get update
    sudo apt-get install -y build-essential pkg-config yasm nasm tar zip

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
    brew update
    brew install nasm pkg-config automake libtool zip
    ;;
  windows)
    if [[ ! -x "C:/msys64/usr/bin/bash.exe" ]]; then
      choco install -y msys2
    fi

    require_env MSYS2_ENV

    case "$MSYS2_ENV" in
      MINGW64)    toolchain_pkg="mingw-w64-x86_64-toolchain" ;;
      MINGW32)    toolchain_pkg="mingw-w64-i686-toolchain" ;;
      CLANGARM64) toolchain_pkg="mingw-w64-clang-aarch64-toolchain" ;;
      CLANGARM32) toolchain_pkg="mingw-w64-clang-armv7-toolchain" ;;
      *)          fail "Unknown MSYS2_ENV: $MSYS2_ENV" ;;
    esac

    C:/msys64/usr/bin/bash.exe -lc "export MSYSTEM=${MSYS2_ENV}; export CHERE_INVOKING=1; pacman -Sy --noconfirm --needed ${toolchain_pkg} make diffutils pkgconf yasm nasm zip"
    ;;
  *)
    fail "Unsupported target platform: $TARGET_PLATFORM"
    ;;
esac
