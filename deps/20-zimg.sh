# zimg: scaling and colorspace conversion (WTFPL). FFmpeg: --enable-libzimg (zscale filter).
DEP_VERSION=3.0.6
DEP_URL="https://github.com/sekrit-twc/zimg/archive/refs/tags/release-${DEP_VERSION}.tar.gz"
DEP_SHA256=be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577

dep_build() {
  fetch_source
  # zimg.cpp relies on <exception> arriving transitively, which libc++ does not guarantee.
  { printf '#include <exception>\n'; cat src/zimg/api/zimg.cpp; } >zimg.cpp.tmp
  mv zimg.cpp.tmp src/zimg/api/zimg.cpp
  ./autogen.sh
  autotools_build --disable-testapp --disable-example --disable-unit-test
}
