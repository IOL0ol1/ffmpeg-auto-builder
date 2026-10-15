# SVT-AV1: AV1 encoder (BSD-3-Clause-Clear). FFmpeg: --enable-libsvtav1. 64-bit only.
DEP_VERSION=4.2.0
DEP_URL="https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v${DEP_VERSION}/SVT-AV1-v${DEP_VERSION}.tar.gz"
DEP_SHA256=c7b13c4a84bd3751aa35fcc72be13e6875467e7c2216879251a486e5b1e4e740
DEP_PLATFORMS="linux/x86_64 linux/arm64 macos/x86_64 macos/arm64 windows/x86_64 windows/arm64"

dep_build() {
  fetch_source
  cmake_build -DBUILD_APPS=OFF -DBUILD_TESTING=OFF -DENABLE_NASM=ON
}
