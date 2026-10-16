# Linux targets, sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain).
#   x86_64, arm64   native, inside a manylinux_2_28 container (glibc 2.28)
#   other archs     cross-compiled inside an Ubuntu 20.04 container (glibc 2.31) with the
#                   distribution's cross compilers; qemu-user runs the result for the smoke test

NASM_VERSION=2.16.03
NASM_SHA256=1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148

# Cross target of an architecture; sets the caller's triple, cpu_family, cpu, ffmpeg_arch,
# endian and qemu (qemu-user binary suffix; empty when the host runs it natively).
linux_cross() {
  case "$1" in
    x86)   triple=i686-linux-gnu      cpu_family=x86 cpu=i686  ffmpeg_arch=x86 endian=little qemu="" ;;
    armv7) triple=arm-linux-gnueabihf cpu_family=arm cpu=armv7 ffmpeg_arch=arm endian=little qemu=arm ;;
    *) return 1 ;;
  esac
}

# The distribution's NASM 2.14 cannot assemble FFmpeg's 32-bit x86 code.
install_nasm_from_source() {
  local archive=/tmp/nasm.tar.xz
  curl -fsSL --retry 3 -o "$archive" \
    "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/nasm-${NASM_VERSION}.tar.xz"
  echo "${NASM_SHA256}  ${archive}" | sha256sum -c - >/dev/null || fail "NASM checksum mismatch"
  tar -xf "$archive" -C /tmp
  (cd "/tmp/nasm-${NASM_VERSION}" && ./configure --prefix=/usr/local >/dev/null && make -j"$(cpu_count)" >/dev/null && make install >/dev/null)
}

platform_install() {
  if command -v dnf >/dev/null 2>&1; then
    # manylinux_2_28 (AlmaLinux 8): already has gcc, cmake and patchelf.
    dnf install -y --setopt=install_weak_deps=False \
      nasm zip unzip xz bzip2 automake autoconf libtool make which
    install_python_build_tools
    command -v cmake >/dev/null || pipx install cmake
    return
  fi

  local triple cpu_family cpu ffmpeg_arch endian qemu
  linux_cross "$TARGET_ARCH" || fail "Unexpected Linux target outside the manylinux container: $TARGET_ARCH"
  export DEBIAN_FRONTEND=noninteractive
  local cross=("gcc-$triple" "g++-$triple")
  if [[ -z "$qemu" ]]; then
    # The i386 C / C++ runtime lets the smoke test run the result natively.
    dpkg --add-architecture i386
    cross+=(libc6:i386 libstdc++6:i386 libgcc-s1:i386)
  else
    cross+=(qemu-user)
  fi
  apt-get update
  apt-get install -y --no-install-recommends \
    build-essential pkg-config zip unzip xz-utils bzip2 automake autoconf libtool make \
    git ca-certificates curl patchelf ccache python3-pip "${cross[@]}"
  install_python_build_tools
  [[ "$cpu_family" != x86 ]] || install_nasm_from_source
  # The distribution's CMake 3.16 is older than some libraries require.
  python3 -m pip install --quiet --user --upgrade cmake
}

platform_toolchain() {
  case "$TARGET_ARCH" in
    x86_64 | arm64)
      export CC=gcc CXX=g++
      return
      ;;
  esac

  local triple cpu_family cpu ffmpeg_arch endian qemu
  linux_cross "$TARGET_ARCH" || fail "Unsupported target: linux/$TARGET_ARCH"
  if [[ "$cpu_family" == x86 ]]; then
    # Any 32-bit x86 CPU still in use has SSE2.
    export CFLAGS="$CFLAGS -msse2 -mfpmath=sse" CXXFLAGS="$CXXFLAGS -msse2 -mfpmath=sse"
  fi
  TARGET_RUNNER="${qemu:+qemu-$qemu -L /usr/$triple}"
  export CC="$triple-gcc" CXX="$triple-g++" AR="$triple-ar" RANLIB="$triple-ranlib"
  export NM="$triple-nm" STRIP="$triple-strip"
  AUTOTOOLS_HOST_ARGS=(--host="$triple")
  write_cross_files Linux "$cpu_family" "$cpu" "$CC" "$CXX" "$AR" "$STRIP" "" "/usr/$triple" "$endian"
  FFMPEG_TOOLCHAIN_ARGS=(
    "--target-os=linux"
    "--arch=$ffmpeg_arch"
    "--enable-cross-compile"
    "--cross-prefix=$triple-"
    "--cc=$CC"
    "--cxx=$CXX"
  )
}
