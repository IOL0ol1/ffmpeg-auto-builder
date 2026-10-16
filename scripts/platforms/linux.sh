# Linux targets, sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain).
#   x86_64, arm64   native, inside a manylinux_2_28 container (glibc 2.28)
#   loongarch64     cross-compiled inside an Ubuntu 24.04 container with Loongson's official
#                   cross toolchain (the architecture starts at glibc 2.36)
#   other archs     cross-compiled inside an Ubuntu 20.04 container (glibc 2.31) with the
#                   distribution's cross compilers
# qemu-user runs the cross-compiled results for the smoke test.

NASM_VERSION=2.16.03
NASM_SHA256=1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148
LOONGARCH_TOOLS_URL=https://github.com/loongson/build-tools/releases/download/2024.11.01/x86_64-cross-tools-loongarch64-binutils_2.43.1-gcc_14.2.0-glibc_2.40.tar.xz
LOONGARCH_TOOLS_SHA256=3405faee1cb757d9e42962013a3fe0dfb62ebf44b4c0739833f4b9528a99a017
LOONGARCH_TOOLS=/opt/cross-tools

# Cross target of an architecture; sets the caller's triple, cpu_family, cpu, ffmpeg_arch,
# endian, qemu (qemu-user binary suffix; empty when the host runs it natively), sysroot and
# ffmpeg_extra (extra configure flags).
linux_cross() {
  ffmpeg_extra=()
  case "$1" in
    x86)         triple=i686-linux-gnu                 cpu_family=x86         cpu=i686        ffmpeg_arch=x86         endian=little qemu="" ;;
    armv7)       triple=arm-linux-gnueabihf            cpu_family=arm         cpu=armv7       ffmpeg_arch=arm         endian=little qemu=arm ;;
    armel)       triple=arm-linux-gnueabi              cpu_family=arm         cpu=armv5te     ffmpeg_arch=arm         endian=little qemu=arm ;;
    ppc64le)     triple=powerpc64le-linux-gnu          cpu_family=ppc64       cpu=ppc64le     ffmpeg_arch=ppc64       endian=little qemu=ppc64le ;;
    s390x)       triple=s390x-linux-gnu                cpu_family=s390x       cpu=s390x       ffmpeg_arch=s390        endian=big    qemu=s390x ;;
    riscv64)     triple=riscv64-linux-gnu              cpu_family=riscv64     cpu=riscv64     ffmpeg_arch=riscv       endian=little qemu=riscv64 ;;
    mips64el)    triple=mips64el-linux-gnuabi64        cpu_family=mips64      cpu=mips64      ffmpeg_arch=mips64      endian=little qemu=mips64el ;;
    mipsel)      triple=mipsel-linux-gnu               cpu_family=mips        cpu=mips32      ffmpeg_arch=mips        endian=little qemu=mipsel ;;
    loongarch64) triple=loongarch64-unknown-linux-gnu  cpu_family=loongarch64 cpu=loongarch64 ffmpeg_arch=loongarch64 endian=little qemu=loongarch64 ;;
    *) return 1 ;;
  esac
  sysroot="/usr/$triple"
  [[ "$1" != loongarch64 ]] || sysroot="$LOONGARCH_TOOLS/target"
  # The DSP ASE checks add -mdsp / -mdspr2 to every file, which the baseline CPUs lack;
  # MSA and MMI are detected at run time.
  case "$1" in
    mips64el | mipsel) ffmpeg_extra=(--disable-mipsdsp --disable-mipsdspr2) ;;
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

install_loongarch_tools() {
  local archive=/tmp/loongarch-tools.tar.xz
  curl -fsSL --retry 3 -o "$archive" "$LOONGARCH_TOOLS_URL"
  echo "${LOONGARCH_TOOLS_SHA256}  ${archive}" | sha256sum -c - >/dev/null || fail "LoongArch toolchain checksum mismatch"
  tar -xf "$archive" -C "$(dirname "$LOONGARCH_TOOLS")"
  rm -f "$archive"
  # The C++ runtime lives next to the compiler; qemu-user only searches the sysroot.
  cp -a "$LOONGARCH_TOOLS"/loongarch64-unknown-linux-gnu/lib/libstdc++.so* \
    "$LOONGARCH_TOOLS"/loongarch64-unknown-linux-gnu/lib/libgcc_s.so* "$LOONGARCH_TOOLS/target/usr/lib64/"
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

  local triple cpu_family cpu ffmpeg_arch endian qemu sysroot ffmpeg_extra
  linux_cross "$TARGET_ARCH" || fail "Unexpected Linux target outside the manylinux container: $TARGET_ARCH"
  export DEBIAN_FRONTEND=noninteractive
  local common=(build-essential pkg-config zip unzip xz-utils bzip2 automake autoconf libtool make
    git ca-certificates curl patchelf ccache)
  apt-get update
  if [[ "$TARGET_ARCH" == loongarch64 ]]; then
    # Ubuntu 24.04: recent enough CMake and qemu-user; Python tools through pipx (PEP 668).
    apt-get install -y --no-install-recommends "${common[@]}" cmake pipx qemu-user
    install_python_build_tools
    install_loongarch_tools
    return
  fi

  local cross=("gcc-$triple" "g++-$triple")
  if [[ -z "$qemu" ]]; then
    # The i386 C / C++ runtime lets the smoke test run the result natively.
    dpkg --add-architecture i386
    apt-get update
    cross+=(libc6:i386 libstdc++6:i386 libgcc-s1:i386)
  else
    cross+=(qemu-user)
  fi
  apt-get install -y --no-install-recommends "${common[@]}" python3-pip "${cross[@]}"
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

  local triple cpu_family cpu ffmpeg_arch endian qemu sysroot ffmpeg_extra
  linux_cross "$TARGET_ARCH" || fail "Unsupported target: linux/$TARGET_ARCH"
  [[ "$TARGET_ARCH" != loongarch64 ]] || export PATH="$LOONGARCH_TOOLS/bin:$PATH"
  if [[ "$cpu_family" == x86 ]]; then
    # Any 32-bit x86 CPU still in use has SSE2.
    export CFLAGS="$CFLAGS -msse2 -mfpmath=sse" CXXFLAGS="$CXXFLAGS -msse2 -mfpmath=sse"
  fi
  TARGET_RUNNER="${qemu:+qemu-$qemu -L $sysroot}"
  export CC="$triple-gcc" CXX="$triple-g++" AR="$triple-ar" RANLIB="$triple-ranlib"
  export NM="$triple-nm" STRIP="$triple-strip"
  AUTOTOOLS_HOST_ARGS=(--host="$triple")
  write_cross_files Linux "$cpu_family" "$cpu" "$CC" "$CXX" "$AR" "$STRIP" "" "$sysroot" "$endian"
  FFMPEG_TOOLCHAIN_ARGS=(
    "--target-os=linux"
    "--arch=$ffmpeg_arch"
    "--enable-cross-compile"
    "--cross-prefix=$triple-"
    "--cc=$CC"
    "--cxx=$CXX"
    ${ffmpeg_extra[@]+"${ffmpeg_extra[@]}"}
  )
}
