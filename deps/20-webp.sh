# libwebp: WebP image codec (BSD-3-Clause). FFmpeg: --enable-libwebp.
DEP_VERSION=1.6.0
DEP_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${DEP_VERSION}.tar.gz"
DEP_SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564

dep_build() {
  fetch_source
  # The AVX2 code needs intrinsics that GCC 9 (the Ubuntu 20.04 cross compiler) lacks;
  # without AVX2 in the SIMD list its files compile to nothing and SSE2 / SSE4.1 remain.
  if [[ "$TARGET_PLATFORM/$TARGET_ARCH" == linux/x86 ]]; then
    sed -i.bak -e 's/"AVX2;SSE41/"SSE41/' -e 's/"_avx2\.c;_sse41/"_sse41/' \
      -e 's/"-mavx2;-msse4\.1/"-msse4.1/' -e 's/"-mno-avx2;-mno-sse4\.1/"-mno-sse4.1/' cmake/cpu.cmake
  fi
  # WebAssembly runs single-threaded (see scripts/platforms/wasm.sh).
  local threads=()
  [[ "$TARGET_PLATFORM" != wasm ]] || threads=(-DWEBP_USE_THREAD=OFF)
  cmake_build -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
    -DWEBP_BUILD_LIBWEBPMUX=ON ${threads[@]+"${threads[@]}"}
}
