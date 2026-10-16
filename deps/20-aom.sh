# libaom: AV1 reference codec (BSD-2-Clause). FFmpeg: --enable-libaom, which also enables
# FFmpeg's libaom decoder wrapper, so the decoder is built too.
DEP_VERSION=3.15.2
DEP_URL="https://storage.googleapis.com/aom-releases/libaom-${DEP_VERSION}.tar.gz"
DEP_SHA256=67bb54b245f33ed98600e08269e6139986e48114e14042474ddd8885801dfddc

dep_build() {
  fetch_source
  # Cross builds must name the target CPU; native builds detect it.
  local cpu=()
  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    windows/x86_64)          cpu=(-DAOM_TARGET_CPU=x86_64) ;;
    windows/x86 | linux/x86) cpu=(-DAOM_TARGET_CPU=x86) ;;
    windows/arm64)           cpu=(-DAOM_TARGET_CPU=arm64) ;;
    # libaom's armv7 NEON code assumes NEON, which the armhf baseline does not guarantee.
    linux/armv7)             cpu=(-DAOM_TARGET_CPU=arm -DENABLE_NEON=0) ;;
    # Portable C elsewhere (armel has no NEON; the others need newer compiler extensions).
    linux/x86_64 | linux/arm64) ;;
    linux/*)                 cpu=(-DAOM_TARGET_CPU=generic) ;;
  esac
  cmake_build -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TESTS=0 -DENABLE_TOOLS=0 \
    ${cpu[@]+"${cpu[@]}"}
}
