#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

require_env TARGET_PLATFORM

case "$TARGET_PLATFORM" in
  linux)
    sudo apt-get update
    sudo apt-get install -y build-essential pkg-config yasm nasm tar zip
    ;;
  macos)
    brew update
    brew install nasm pkg-config automake libtool zip
    ;;
  windows)
    if [[ ! -x "C:/msys64/usr/bin/bash.exe" ]]; then
      choco install -y msys2
    fi

    C:/msys64/usr/bin/bash.exe -lc "export MSYSTEM=MINGW64; export CHERE_INVOKING=1; pacman -Sy --noconfirm --needed mingw-w64-x86_64-toolchain make diffutils pkgconf yasm nasm zip"
    ;;
  *)
    fail "Unsupported target platform: $TARGET_PLATFORM"
    ;;
esac
