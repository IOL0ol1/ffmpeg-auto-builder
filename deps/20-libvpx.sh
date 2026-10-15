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
    macos/x86_64)   target=x86_64-darwin20-gcc ;;
    macos/arm64)    target=arm64-darwin20-gcc ;;
    windows/x86_64) target=x86_64-win64-gcc ;;
    windows/x86)    target=x86-win32-gcc ;;
    windows/arm64)  target=arm64-win64-gcc ;;
  esac
  ./configure --prefix="$DEPS_PREFIX" --target="$target" \
    --enable-static --disable-shared --enable-pic --enable-vp9-highbitdepth \
    --disable-examples --disable-tools --disable-docs --disable-unit-tests
  make -j"$(cpu_count)"
  make install
}
