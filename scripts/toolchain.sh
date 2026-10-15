#!/usr/bin/env bash
# Toolchain setup shared by scripts/build-deps.sh and scripts/build-ffmpeg.sh for the
# targets that get third-party libraries:
#   linux/x86_64, linux/arm64    native, inside a manylinux_2_28 container (glibc 2.28)
#   macos/x86_64, macos/arm64    native on a runner of that architecture
#   windows/x86_64|x86|arm64     cross-compiled with llvm-mingw ($LLVM_MINGW) on Linux
#
# setup_toolchain exports CC/CXX/... and sets, for the build helpers and FFmpeg:
#   AUTOTOOLS_HOST_ARGS, CMAKE_TOOLCHAIN_ARGS, MESON_CROSS_ARGS  (arrays)
#   FFMPEG_TOOLCHAIN_ARGS                                         (array)
#   TOOLCHAIN_BIN                                                 (windows: DLLs to bundle)

# Targets that get third-party libraries; the others build FFmpeg on its own.
deps_supported() {
  case "${TARGET_PLATFORM}/${TARGET_ARCH}" in
    linux/x86_64 | linux/arm64 | macos/x86_64 | macos/arm64 | windows/x86_64 | windows/x86 | windows/arm64) return 0 ;;
    *) return 1 ;;
  esac
}

mingw_triple() {
  case "$TARGET_ARCH" in
    x86_64) echo x86_64-w64-mingw32 ;;
    x86)    echo i686-w64-mingw32 ;;
    arm64)  echo aarch64-w64-mingw32 ;;
    *)      fail "No MinGW triple for $TARGET_ARCH" ;;
  esac
}

setup_toolchain() {
  require_env TARGET_PLATFORM
  require_env TARGET_ARCH
  require_env DEPS_PREFIX

  AUTOTOOLS_HOST_ARGS=()
  CMAKE_TOOLCHAIN_ARGS=()
  MESON_CROSS_ARGS=()
  FFMPEG_TOOLCHAIN_ARGS=()
  TOOLCHAIN_BIN=""

  # Only look for libraries in the dependency prefix, never on the build host.
  export PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/share/pkgconfig"
  unset PKG_CONFIG_PATH
  export CPPFLAGS="-I$DEPS_PREFIX/include"
  export CFLAGS="-O2 -fPIC"
  export CXXFLAGS="-O2 -fPIC"
  export LDFLAGS="-L$DEPS_PREFIX/lib"

  case "$TARGET_PLATFORM" in
    linux)
      export CC=gcc CXX=g++
      ;;
    macos)
      export CC=clang CXX=clang++
      export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
      ;;
    windows)
      require_env LLVM_MINGW
      local triple cpu_family cpu ffmpeg_arch
      triple="$(mingw_triple)"
      case "$TARGET_ARCH" in
        x86_64) cpu_family=x86_64 cpu=x86_64 ffmpeg_arch=x86_64 ;;
        x86)    cpu_family=x86 cpu=i686 ffmpeg_arch=x86 ;;
        arm64)  cpu_family=aarch64 cpu=aarch64 ffmpeg_arch=aarch64 ;;
      esac
      export PATH="$LLVM_MINGW/bin:$PATH"
      export CC="$triple-clang" CXX="$triple-clang++" AR="$triple-ar" RANLIB="$triple-ranlib"
      export NM="$triple-nm" STRIP="$triple-strip" WINDRES="$triple-windres" RC="$triple-windres"
      # PE has no -fPIC; static runtime avoids shipping libc++ / libunwind DLLs.
      export CFLAGS="-O2" CXXFLAGS="-O2"
      export LDFLAGS="-L$DEPS_PREFIX/lib -static"
      TOOLCHAIN_BIN="$LLVM_MINGW/$triple/bin"
      AUTOTOOLS_HOST_ARGS=(--host="$triple")

      local toolchain_dir="$DEPS_PREFIX/../toolchain"
      mkdir -p "$toolchain_dir"
      cat >"$toolchain_dir/windows.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR $cpu)
set(CMAKE_C_COMPILER $triple-clang)
set(CMAKE_CXX_COMPILER $triple-clang++)
set(CMAKE_RC_COMPILER $triple-windres)
set(CMAKE_AR $LLVM_MINGW/bin/$triple-ar)
set(CMAKE_RANLIB $LLVM_MINGW/bin/$triple-ranlib)
set(CMAKE_FIND_ROOT_PATH $DEPS_PREFIX $LLVM_MINGW/$triple)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
      cat >"$toolchain_dir/windows.meson" <<EOF
[binaries]
c = '$triple-clang'
cpp = '$triple-clang++'
ar = '$triple-ar'
strip = '$triple-strip'
windres = '$triple-windres'
pkg-config = 'pkg-config'

[host_machine]
system = 'windows'
cpu_family = '$cpu_family'
cpu = '$cpu'
endian = 'little'
EOF
      CMAKE_TOOLCHAIN_ARGS=(-DCMAKE_TOOLCHAIN_FILE="$toolchain_dir/windows.cmake")
      MESON_CROSS_ARGS=(--cross-file="$toolchain_dir/windows.meson")
      FFMPEG_TOOLCHAIN_ARGS=(
        "--target-os=mingw32"
        "--arch=$ffmpeg_arch"
        "--enable-cross-compile"
        "--cross-prefix=$triple-"
        "--cc=$CC"
        "--cxx=$CXX"
        "--extra-ldflags=-static"
      )
      ;;
    *)
      fail "Unsupported platform for third-party libraries: $TARGET_PLATFORM"
      ;;
  esac

  # FFmpeg finds the libraries through pkg-config; link them statically.
  FFMPEG_TOOLCHAIN_ARGS+=(
    "--pkg-config=pkg-config"
    "--pkg-config-flags=--static"
    "--extra-cflags=-I$DEPS_PREFIX/include"
    "--extra-ldflags=-L$DEPS_PREFIX/lib"
  )
}
