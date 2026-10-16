# x264: H.264 encoder (GPL). FFmpeg: --enable-libx264 (requires --enable-gpl).
DEP_VERSION=b35605ace3ddf7c1a5d67a2eb553f034aef41d55
DEP_URL="https://code.videolan.org/videolan/x264/-/archive/${DEP_VERSION}/x264-${DEP_VERSION}.tar.bz2"
DEP_SHA256=6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224

dep_build() {
  fetch_source
  # x264 has no assembly for these, needs ARMv6T2 + NEON on 32-bit ARM, and would build MIPS
  # MSA code without a run-time check.
  # On 32-bit x86 Android (always PIC) the inline assembly runs out of registers.
  local asm=()
  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    linux/armel | linux/s390x | linux/riscv64 | linux/mips64el | linux/mipsel | android/x86) asm=(--disable-asm) ;;
  esac
  # x264's config.sub predates riscv64, loongarch64 and Emscripten.
  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    linux/x86_64 | linux/arm64) ;;
    linux/* | wasm/*) update_config_scripts ;;
  esac
  # x264 does not know Emscripten; a generic 32-bit host without threads builds portable C.
  local host=(${AUTOTOOLS_HOST_ARGS[@]+"${AUTOTOOLS_HOST_ARGS[@]}"})
  [[ "$TARGET_PLATFORM" != wasm ]] || { host=(--host=i686-gnu); asm=(--disable-asm --disable-thread); }
  local kind=(--enable-static) target=install-lib-static
  dep_shared && kind=(--enable-shared) target=install-lib-shared
  ./configure --prefix="$DEPS_PREFIX" ${host[@]+"${host[@]}"} \
    "${kind[@]}" --enable-pic --disable-cli ${asm[@]+"${asm[@]}"} \
    --disable-lavf --disable-swscale --disable-ffms --disable-gpac --disable-lsmash
  make -j"$(cpu_count)"
  make "$target"
}
