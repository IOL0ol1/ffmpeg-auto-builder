#!/usr/bin/env bash
# Toolchain setup shared by scripts/build-deps.sh and scripts/build-ffmpeg.sh. The
# per-platform part is platform_toolchain in scripts/platforms/<platform>.sh.
#
# setup_toolchain exports CC/CXX/... and sets, for the build helpers and FFmpeg:
#   AUTOTOOLS_HOST_ARGS, CMAKE_TOOLCHAIN_ARGS, MESON_CROSS_ARGS  (arrays)
#   FFMPEG_TOOLCHAIN_ARGS                                         (array)
#   TARGET_RUNNER   command prefix that runs target binaries on the build host, or
#                   "none" when they cannot run there
#   TOOLCHAIN_BIN   windows: directory of the toolchain's runtime DLLs

# Write a CMake toolchain file and a Meson cross file for a cross target.
# write_cross_files <system> <cpu_family> <cpu> <c> <c++> <ar> <strip> [windres] [find-root] [endian]
write_cross_files() {
  local system="$1" cpu_family="$2" cpu="$3" cc="$4" cxx="$5" ar="$6" strip="$7" windres="${8:-}" find_root="${9:-}" endian="${10:-little}"
  local dir="$DEPS_PREFIX/../toolchain"
  mkdir -p "$dir"

  {
    echo "set(CMAKE_SYSTEM_NAME $system)"
    echo "set(CMAKE_SYSTEM_PROCESSOR $cpu)"
    echo "set(CMAKE_C_COMPILER $cc)"
    echo "set(CMAKE_CXX_COMPILER $cxx)"
    echo "set(CMAKE_AR $(command -v "$ar"))"
    echo "set(CMAKE_RANLIB $(command -v "$RANLIB"))"
    [[ -z "$windres" ]] || echo "set(CMAKE_RC_COMPILER $windres)"
    echo "set(CMAKE_FIND_ROOT_PATH $DEPS_PREFIX $find_root)"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)"
  } >"$dir/cross.cmake"

  {
    echo "[binaries]"
    echo "c = '$cc'"
    echo "cpp = '$cxx'"
    echo "ar = '$ar'"
    echo "strip = '$strip'"
    [[ -z "$windres" ]] || echo "windres = '$windres'"
    echo "pkg-config = 'pkg-config'"
    echo
    echo "[host_machine]"
    echo "system = '$(echo "$system" | tr '[:upper:]' '[:lower:]')'"
    echo "cpu_family = '$cpu_family'"
    echo "cpu = '$cpu'"
    echo "endian = '$endian'"
  } >"$dir/cross.meson"

  CMAKE_TOOLCHAIN_ARGS=(-DCMAKE_TOOLCHAIN_FILE="$dir/cross.cmake")
  MESON_CROSS_ARGS=(--cross-file="$dir/cross.meson")
}

setup_toolchain() {
  require_env TARGET_PLATFORM
  require_env TARGET_ARCH
  require_env DEPS_PREFIX

  AUTOTOOLS_HOST_ARGS=()
  CMAKE_TOOLCHAIN_ARGS=()
  MESON_CROSS_ARGS=()
  FFMPEG_TOOLCHAIN_ARGS=()
  TARGET_RUNNER=""
  TOOLCHAIN_BIN=""

  # Only look for libraries in the dependency prefix, never on the build host.
  export PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/share/pkgconfig"
  unset PKG_CONFIG_PATH
  export CPPFLAGS="-I$DEPS_PREFIX/include"
  export CFLAGS="-O2 -fPIC"
  export CXXFLAGS="-O2 -fPIC"
  export LDFLAGS="-L$DEPS_PREFIX/lib"

  local platform_file
  platform_file="$(dirname "${BASH_SOURCE[0]}")/platforms/$TARGET_PLATFORM.sh"
  [[ -f "$platform_file" ]] || fail "Unsupported target: $TARGET_PLATFORM/$TARGET_ARCH"
  source "$platform_file"
  platform_toolchain

  # FFmpeg finds the libraries through pkg-config; link them statically.
  FFMPEG_TOOLCHAIN_ARGS+=(
    "--pkg-config=pkg-config"
    "--pkg-config-flags=--static"
    "--extra-cflags=-I$DEPS_PREFIX/include"
    "--extra-ldflags=-L$DEPS_PREFIX/lib"
  )
}
