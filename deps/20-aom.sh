# libaom: AV1 reference codec (BSD-2-Clause). FFmpeg: --enable-libaom, which also enables
# FFmpeg's libaom decoder wrapper, so the decoder is built too.
DEP_VERSION=3.15.2
DEP_URL="https://storage.googleapis.com/aom-releases/libaom-${DEP_VERSION}.tar.gz"
DEP_SHA256=67bb54b245f33ed98600e08269e6139986e48114e14042474ddd8885801dfddc

dep_build() {
  fetch_source
  local cpu=()
  if [[ "$TARGET_PLATFORM" == "windows" ]]; then
    case "$TARGET_ARCH" in
      x86_64) cpu=(-DAOM_TARGET_CPU=x86_64) ;;
      x86)    cpu=(-DAOM_TARGET_CPU=x86) ;;
      arm64)  cpu=(-DAOM_TARGET_CPU=arm64) ;;
    esac
  fi
  cmake_build -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TESTS=0 -DENABLE_TOOLS=0 \
    ${cpu[@]+"${cpu[@]}"}
}
