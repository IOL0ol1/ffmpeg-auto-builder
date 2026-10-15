#!/usr/bin/env bash
# Toolchain setup shared by scripts/build-deps.sh and scripts/build-ffmpeg.sh. Every target
# gets the third-party libraries:
#   linux/x86_64, linux/arm64    native, inside a manylinux_2_28 container (glibc 2.28)
#   linux/x86, linux/armv7       cross-compiled inside an Ubuntu 20.04 container (glibc 2.31)
#   macos/x86_64, macos/arm64    native on a runner of that architecture
#   windows/x86_64|x86|arm64     cross-compiled with llvm-mingw ($LLVM_MINGW) on Linux
#
# setup_toolchain exports CC/CXX/... and sets, for the build helpers and FFmpeg:
#   AUTOTOOLS_HOST_ARGS, CMAKE_TOOLCHAIN_ARGS, MESON_CROSS_ARGS  (arrays)
#   FFMPEG_TOOLCHAIN_ARGS                                         (array)
#   TARGET_RUNNER   command prefix that runs target binaries on the build host, or
#                   "none" when they cannot run there (Windows)
#   TOOLCHAIN_BIN   windows: directory of the toolchain's runtime DLLs

mingw_triple() {
  case "$TARGET_ARCH" in
    x86_64) echo x86_64-w64-mingw32 ;;
    x86)    echo i686-w64-mingw32 ;;
    arm64)  echo aarch64-w64-mingw32 ;;
    *)      fail "No MinGW triple for $TARGET_ARCH" ;;
  esac
}

# Write a CMake toolchain file and a Meson cross file for a cross target.
# write_cross_files <system: Linux|Windows> <cpu_family> <cpu> <c> <c++> <ar> <strip> [windres] [find-root]
write_cross_files() {
  local system="$1" cpu_family="$2" cpu="$3" cc="$4" cxx="$5" ar="$6" strip="$7" windres="${8:-}" find_root="${9:-}"
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
    echo "endian = 'little'"
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

  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    linux/x86_64 | linux/arm64)
      export CC=gcc CXX=g++
      ;;

    linux/x86 | linux/armv7)
      local triple cpu_family cpu ffmpeg_arch
      case "$TARGET_ARCH" in
        x86)
          triple=i686-linux-gnu cpu_family=x86 cpu=i686 ffmpeg_arch=x86
          # Any 32-bit x86 CPU still in use has SSE2.
          export CFLAGS="$CFLAGS -msse2 -mfpmath=sse" CXXFLAGS="$CXXFLAGS -msse2 -mfpmath=sse"
          # The Ubuntu container has the i386 C runtime installed to run the result.
          TARGET_RUNNER=""
          ;;
        armv7)
          # armhf baseline (ARMv7 + VFPv3-D16); FFmpeg detects NEON at run time.
          triple=arm-linux-gnueabihf cpu_family=arm cpu=armv7 ffmpeg_arch=arm
          TARGET_RUNNER="qemu-arm -L /usr/$triple"
          ;;
      esac
      export CC="$triple-gcc" CXX="$triple-g++" AR="$triple-ar" RANLIB="$triple-ranlib"
      export NM="$triple-nm" STRIP="$triple-strip"
      AUTOTOOLS_HOST_ARGS=(--host="$triple")
      write_cross_files Linux "$cpu_family" "$cpu" "$CC" "$CXX" "$AR" "$STRIP" "" "/usr/$triple"
      FFMPEG_TOOLCHAIN_ARGS=(
        "--target-os=linux"
        "--arch=$ffmpeg_arch"
        "--enable-cross-compile"
        "--cross-prefix=$triple-"
        "--cc=$CC"
        "--cxx=$CXX"
      )
      ;;

    macos/*)
      export CC=clang CXX=clang++
      export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
      ;;

    windows/*)
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
      # Windows 10+ requires SSE2; i686 clang does not enable it by default.
      if [[ "$TARGET_ARCH" == "x86" ]]; then
        export CFLAGS="$CFLAGS -msse2 -mfpmath=sse" CXXFLAGS="$CXXFLAGS -msse2 -mfpmath=sse"
      fi
      export LDFLAGS="-L$DEPS_PREFIX/lib -static"
      TOOLCHAIN_BIN="$LLVM_MINGW/$triple/bin"
      TARGET_RUNNER="none"
      AUTOTOOLS_HOST_ARGS=(--host="$triple")
      write_cross_files Windows "$cpu_family" "$cpu" "$CC" "$CXX" "$AR" "$STRIP" "$WINDRES" "$LLVM_MINGW/$triple"
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
      fail "Unsupported target: $TARGET_PLATFORM/$TARGET_ARCH"
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
