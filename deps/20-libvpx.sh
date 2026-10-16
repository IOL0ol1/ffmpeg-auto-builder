# libvpx: VP8 / VP9 codec (BSD-3-Clause). FFmpeg: --enable-libvpx.
DEP_VERSION=1.17.0
DEP_URL="https://github.com/webmproject/libvpx/archive/refs/tags/v${DEP_VERSION}.tar.gz"
DEP_SHA256=1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a

dep_build() {
  fetch_source
  local target
  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    linux/x86_64)   target=x86_64-linux-gcc ;;
    linux/arm64)    target=arm64-linux-gcc ;;
    linux/x86)      target=x86-linux-gcc ;;
    linux/armv7)    target=armv7-linux-gcc ;;
    linux/ppc64le)  target=ppc64le-linux-gcc ;;
    # No libvpx target (or none without newer compiler extensions): portable C.
    linux/*)        target=generic-gnu ;;
    macos/x86_64)   target=x86_64-darwin20-gcc ;;
    macos/arm64)    target=arm64-darwin20-gcc ;;
    windows/x86_64) target=x86_64-win64-gcc ;;
    windows/x86)    target=x86-win32-gcc ;;
    windows/arm64)  target=arm64-win64-gcc ;;
    android/arm64)  target=arm64-android-gcc ;;
    android/armv7)  target=armv7-android-gcc ;;
    android/x86_64) target=x86_64-android-gcc ;;
    android/x86)    target=x86-android-gcc ;;
  esac
  # Cross builds use ${CROSS}as / ar / ...; CC alone does not set them. x86 assembles with nasm.
  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    linux/x86_64 | linux/arm64 | linux/x86) ;;
    linux/*) export CROSS="${CC%gcc}" ;;
    # The NDK has no GNU assembler; libvpx uses clang's integrated one when AS is clang.
    android/arm*) export AS="$CC" ;;
  esac
  ./configure --prefix="$DEPS_PREFIX" --target="$target" \
    --enable-static --disable-shared --enable-pic --enable-vp9-highbitdepth \
    --disable-examples --disable-tools --disable-docs --disable-unit-tests
  make -j"$(cpu_count)"
  make install
}
