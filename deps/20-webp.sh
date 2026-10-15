# libwebp: WebP image codec (BSD-3-Clause). FFmpeg: --enable-libwebp.
DEP_VERSION=1.6.0
DEP_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${DEP_VERSION}.tar.gz"
DEP_SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564

dep_build() {
  fetch_source
  cmake_build -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
    -DWEBP_BUILD_LIBWEBPMUX=ON
}
