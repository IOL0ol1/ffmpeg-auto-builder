#!/usr/bin/env bash
# Install the build tools for one target. Windows targets are cross-compiled on Linux with
# llvm-mingw; linux/x86_64 and linux/arm64 run inside a manylinux_2_28 container, linux/x86 and
# linux/armv7 inside Ubuntu 20.04.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

require_env TARGET_PLATFORM
require_env TARGET_ARCH

LLVM_MINGW_VERSION=20261006
LLVM_MINGW_SHA256=5f9c6ed95b2d4bdb2869a488c5fd5857fbdabcf288a0aa3eb1da43f6a08d8ab4
NASM_VERSION=2.16.03
NASM_SHA256=1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148

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

case "$TARGET_PLATFORM" in
  linux)
    if command -v dnf >/dev/null 2>&1; then
      # manylinux_2_28 (AlmaLinux 8): already has gcc, cmake and patchelf.
      dnf install -y --setopt=install_weak_deps=False \
        nasm zip unzip xz bzip2 automake autoconf libtool make which
      install_python_build_tools
      command -v cmake >/dev/null || pipx install cmake
    else
      # Ubuntu 20.04 container (glibc 2.31) for the 32-bit targets, cross-compiled.
      export DEBIAN_FRONTEND=noninteractive
      case "$TARGET_ARCH" in
        x86)
          # The i386 C / C++ runtime lets the smoke test run the result natively.
          dpkg --add-architecture i386
          cross=(gcc-i686-linux-gnu g++-i686-linux-gnu libc6:i386 libstdc++6:i386 libgcc-s1:i386)
          ;;
        armv7)
          # qemu-user runs the result for the smoke test.
          cross=(gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf qemu-user)
          ;;
        *) fail "Unexpected Linux target outside the manylinux container: $TARGET_ARCH" ;;
      esac
      apt-get update
      apt-get install -y --no-install-recommends \
        build-essential pkg-config zip unzip xz-utils bzip2 automake autoconf libtool make \
        git ca-certificates curl patchelf ccache python3-pip "${cross[@]}"
      install_python_build_tools
      # The distribution's NASM 2.14 cannot assemble FFmpeg's 32-bit x86 code.
      archive=/tmp/nasm.tar.xz
      curl -fsSL --retry 3 -o "$archive" \
        "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/nasm-${NASM_VERSION}.tar.xz"
      echo "${NASM_SHA256}  ${archive}" | sha256sum -c - >/dev/null || fail "NASM checksum mismatch"
      tar -xf "$archive" -C /tmp
      (cd "/tmp/nasm-${NASM_VERSION}" && ./configure --prefix=/usr/local >/dev/null && make -j"$(cpu_count)" >/dev/null && make install >/dev/null)
      # The distribution's CMake 3.16 is older than some libraries require.
      python3 -m pip install --quiet --user --upgrade cmake
    fi
    ;;

  macos)
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
      brew install nasm pkg-config ccache meson ninja automake autoconf libtool
    ;;

  windows)
    sudo apt-get update
    sudo apt-get install -y nasm pkg-config ccache zip unzip automake autoconf libtool cmake pipx
    install_python_build_tools

    toolchain_root="${RUNNER_TOOL_CACHE:-/opt}/llvm-mingw-$LLVM_MINGW_VERSION"
    if [[ ! -x "$toolchain_root/bin/clang" ]]; then
      archive="${RUNNER_TEMP:-/tmp}/llvm-mingw.tar.xz"
      curl -fsSL --retry 3 -o "$archive" \
        "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-x86_64.tar.xz"
      echo "${LLVM_MINGW_SHA256}  ${archive}" | sha256sum -c - >/dev/null || fail "llvm-mingw checksum mismatch"
      mkdir -p "$toolchain_root"
      tar -xf "$archive" -C "$toolchain_root" --strip-components=1
    fi
    export_env LLVM_MINGW "$toolchain_root"
    ;;

  *)
    fail "Unsupported target platform: $TARGET_PLATFORM"
    ;;
esac
