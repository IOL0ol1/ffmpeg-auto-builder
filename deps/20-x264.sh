# x264: H.264 encoder (GPL). FFmpeg: --enable-libx264 (requires --enable-gpl).
DEP_VERSION=b35605ace3ddf7c1a5d67a2eb553f034aef41d55
DEP_URL="https://code.videolan.org/videolan/x264/-/archive/${DEP_VERSION}/x264-${DEP_VERSION}.tar.bz2"
DEP_SHA256=6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224

dep_build() {
  fetch_source
  # x264 has no assembly for these, needs ARMv6T2 + NEON on 32-bit ARM, and would build MIPS
  # MSA code without a run-time check.
  local asm=()
  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    linux/armel | linux/s390x | linux/riscv64 | linux/mips64el | linux/mipsel) asm=(--disable-asm) ;;
  esac
  ./configure --prefix="$DEPS_PREFIX" ${AUTOTOOLS_HOST_ARGS[@]+"${AUTOTOOLS_HOST_ARGS[@]}"} \
    --enable-static --enable-pic --disable-cli ${asm[@]+"${asm[@]}"} \
    --disable-lavf --disable-swscale --disable-ffms --disable-gpac --disable-lsmash
  make -j"$(cpu_count)"
  make install-lib-static
}
