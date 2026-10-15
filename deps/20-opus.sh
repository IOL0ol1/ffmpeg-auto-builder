# Opus: audio codec (BSD-3-Clause). FFmpeg: --enable-libopus.
DEP_VERSION=1.5.2
DEP_URL="https://github.com/xiph/opus/releases/download/v${DEP_VERSION}/opus-${DEP_VERSION}.tar.gz"
DEP_SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1

dep_build() {
  fetch_source
  # Runtime CPU detection has no Windows-on-ARM implementation; NEON is mandatory on AArch64.
  local rtcd=()
  [[ "$TARGET_PLATFORM/$TARGET_ARCH" == "windows/arm64" ]] && rtcd=(--disable-rtcd)
  autotools_build --disable-doc --disable-extra-programs ${rtcd[@]+"${rtcd[@]}"}
}
