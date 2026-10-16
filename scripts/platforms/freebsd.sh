# FreeBSD targets, sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain): cross-compiled on Ubuntu with clang and lld
# against the official base system of FreeBSD 14.4, the oldest supported release (the
# results also run on 15.x).

FREEBSD_VERSION=14.4
FREEBSD_BASE_SHA256_x86_64=769f60a6eea2938ad6b7943cfbcc17dfaf7d1f7ba59a32b869a00349302df853
FREEBSD_BASE_SHA256_arm64=c456bf75ee3d0b4da0b0b527402b0a9e61497f02756b2cc5801b51e80b3f90c4

# Sets the caller's url_arch (download.freebsd.org path), triple, cpu_family and ffmpeg_arch.
freebsd_target() {
  case "$1" in
    x86_64) url_arch=amd64          triple=x86_64-unknown-freebsd$FREEBSD_VERSION  cpu_family=x86_64  ffmpeg_arch=x86_64 ;;
    arm64)  url_arch=arm64/aarch64  triple=aarch64-unknown-freebsd$FREEBSD_VERSION cpu_family=aarch64 ffmpeg_arch=aarch64 ;;
    *) return 1 ;;
  esac
}

platform_install() {
  sudo apt-get update
  sudo apt-get install -y nasm pkg-config ccache zip unzip automake autoconf libtool cmake pipx \
    clang lld llvm patchelf
  install_python_build_tools

  local url_arch triple cpu_family ffmpeg_arch
  freebsd_target "$TARGET_ARCH" || fail "Unsupported target: freebsd/$TARGET_ARCH"
  local sha_var="FREEBSD_BASE_SHA256_$TARGET_ARCH"
  local sysroot="${RUNNER_TEMP:-/tmp}/freebsd-$FREEBSD_VERSION-$TARGET_ARCH"
  local archive="${RUNNER_TEMP:-/tmp}/freebsd-base.txz"
  curl -fsSL --retry 3 -o "$archive" \
    "https://download.freebsd.org/releases/$url_arch/$FREEBSD_VERSION-RELEASE/base.txz"
  echo "${!sha_var}  ${archive}" | sha256sum -c - >/dev/null || fail "FreeBSD base.txz checksum mismatch"
  # Headers and libraries are all the sysroot needs.
  mkdir -p "$sysroot"
  tar -xf "$archive" -C "$sysroot" ./lib ./usr/include ./usr/lib
  rm -f "$archive"
  export_env FREEBSD_SYSROOT "$sysroot"
}

platform_toolchain() {
  require_env FREEBSD_SYSROOT
  local url_arch triple cpu_family ffmpeg_arch
  freebsd_target "$TARGET_ARCH" || fail "Unsupported target: freebsd/$TARGET_ARCH"

  local dir="$DEPS_PREFIX/../toolchain" tool
  mkdir -p "$dir"
  # lld only for link steps: build system checks fail on unused flags (-Werror=unused-...).
  for tool in clang clang++; do
    cat >"$dir/$tool" <<EOF
#!/bin/sh
for arg; do
  case "\$arg" in -c | -E | -S) exec $tool --target=$triple --sysroot="$FREEBSD_SYSROOT" "\$@" ;; esac
done
exec $tool --target=$triple --sysroot="$FREEBSD_SYSROOT" -fuse-ld=lld "\$@"
EOF
    chmod +x "$dir/$tool"
  done
  export CC="$dir/clang" CXX="$dir/clang++"
  export AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm STRIP=llvm-strip
  # Meson installs pkg-config files for FreeBSD hosts into libdata/pkgconfig.
  export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:$DEPS_PREFIX/libdata/pkgconfig"
  TARGET_RUNNER="none"
  AUTOTOOLS_HOST_ARGS=(--host="$triple")
  write_cross_files FreeBSD "$cpu_family" "$cpu_family" "$CC" "$CXX" "$AR" "$STRIP" "" "$FREEBSD_SYSROOT"
  FFMPEG_TOOLCHAIN_ARGS=(
    "--target-os=freebsd"
    "--arch=$ffmpeg_arch"
    "--enable-cross-compile"
    "--cc=$CC"
    "--cxx=$CXX"
    "--ar=$AR"
    "--ranlib=$RANLIB"
    "--nm=$NM"
    "--strip=$STRIP"
  )
}
