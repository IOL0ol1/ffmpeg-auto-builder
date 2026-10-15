# SoX Resampler (LGPL-2.1-or-later). FFmpeg: --enable-libsoxr.
DEP_VERSION=0.1.3
DEP_URL="https://downloads.sourceforge.net/project/soxr/soxr-${DEP_VERSION}-Source.tar.xz"
DEP_SHA256=b111c15fdc8c029989330ff559184198c161100a59312f5dc19ddeb9b5a15889

dep_build() {
  fetch_source
  cmake_build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DWITH_OPENMP=OFF -DWITH_LSR_BINDINGS=OFF
}
