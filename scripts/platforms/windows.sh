# Windows targets, sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain): cross-compiled on Ubuntu with llvm-mingw.

LLVM_MINGW_VERSION=20261006
LLVM_MINGW_SHA256=5f9c6ed95b2d4bdb2869a488c5fd5857fbdabcf288a0aa3eb1da43f6a08d8ab4

mingw_triple() {
  case "$TARGET_ARCH" in
    x86_64) echo x86_64-w64-mingw32 ;;
    x86)    echo i686-w64-mingw32 ;;
    arm64)  echo aarch64-w64-mingw32 ;;
    *)      fail "No MinGW triple for $TARGET_ARCH" ;;
  esac
}

platform_install() {
  sudo apt-get update
  sudo apt-get install -y nasm pkg-config ccache zip unzip automake autoconf libtool cmake pipx
  install_python_build_tools

  local toolchain_root="${RUNNER_TOOL_CACHE:-/opt}/llvm-mingw-$LLVM_MINGW_VERSION"
  if [[ ! -x "$toolchain_root/bin/clang" ]]; then
    local archive="${RUNNER_TEMP:-/tmp}/llvm-mingw.tar.xz"
    curl -fsSL --retry 3 -o "$archive" \
      "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-x86_64.tar.xz"
    echo "${LLVM_MINGW_SHA256}  ${archive}" | sha256sum -c - >/dev/null || fail "llvm-mingw checksum mismatch"
    mkdir -p "$toolchain_root"
    tar -xf "$archive" -C "$toolchain_root" --strip-components=1
  fi
  export_env LLVM_MINGW "$toolchain_root"
}

platform_toolchain() {
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
  # -static keeps the C++ runtime out of DLLs; with shared third-party libraries it would also
  # skip their import libraries, so then the runtime DLLs are shipped instead.
  local static=(-static)
  [[ "${DEPS_LINKAGE:-static}" == static ]] || static=()
  export LDFLAGS="-L$DEPS_PREFIX/lib ${static[*]}"
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
    ${static[@]+"--extra-ldflags=${static[*]}"}
  )
}
