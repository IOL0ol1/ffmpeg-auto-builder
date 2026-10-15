# x264: H.264 encoder (GPL). FFmpeg: --enable-libx264 (requires --enable-gpl).
DEP_VERSION=b35605ace3ddf7c1a5d67a2eb553f034aef41d55
DEP_URL="https://code.videolan.org/videolan/x264/-/archive/${DEP_VERSION}/x264-${DEP_VERSION}.tar.bz2"
DEP_SHA256=6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224

dep_build() {
  fetch_source
  ./configure --prefix="$DEPS_PREFIX" ${AUTOTOOLS_HOST_ARGS[@]+"${AUTOTOOLS_HOST_ARGS[@]}"} \
    --enable-static --enable-pic --disable-cli \
    --disable-lavf --disable-swscale --disable-ffms --disable-gpac --disable-lsmash
  make -j"$(cpu_count)"
  make install-lib-static
}
