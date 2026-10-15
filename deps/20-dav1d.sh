# dav1d: AV1 decoder (BSD-2-Clause). FFmpeg: --enable-libdav1d.
DEP_VERSION=1.5.4
DEP_URL="https://downloads.videolan.org/pub/videolan/dav1d/${DEP_VERSION}/dav1d-${DEP_VERSION}.tar.xz"
DEP_SHA256=686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5

dep_build() {
  fetch_source
  meson_build -Denable_tools=false -Denable_tests=false -Denable_examples=false
}
