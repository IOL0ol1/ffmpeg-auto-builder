# libaom: AV1 reference codec (BSD-2-Clause). FFmpeg: --enable-libaom, which also enables
# FFmpeg's libaom decoder wrapper, so the decoder is built too.
DEP_VERSION=3.15.2
DEP_URL="https://storage.googleapis.com/aom-releases/libaom-${DEP_VERSION}.tar.gz"
DEP_SHA256=67bb54b245f33ed98600e08269e6139986e48114e14042474ddd8885801dfddc
# With CMake's iOS-like system names libaom exports symbols through a GNU version script,
# which Apple's linker cannot read; it stays static there (linked into libavcodec).
case "$TARGET_PLATFORM" in ios | tvos | visionos) DEP_SHARED=no ;; esac

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
    freebsd/x86_64)          cpu=(-DAOM_TARGET_CPU=x86_64) ;;
    # libaom's arm64 run-time CPU detection does not know FreeBSD; NEON is always there.
    freebsd/arm64)           cpu=(-DAOM_TARGET_CPU=arm64 -DCONFIG_RUNTIME_CPU_DETECT=0) ;;
    # With CMake's iOS / tvOS system names libaom assembles x86 code as ELF, not Mach-O.
    ios/sim_x86_64 | tvos/sim_x86_64) cpu=(-DAOM_TARGET_CPU=generic) ;;
    maccatalyst/x86_64)      cpu=(-DAOM_TARGET_CPU=x86_64) ;;
    ios/* | tvos/* | visionos/* | maccatalyst/*)    cpu=(-DAOM_TARGET_CPU=arm64) ;;
    # WebAssembly runs single-threaded (see scripts/platforms/wasm.sh).
    wasm/*)                  cpu=(-DAOM_TARGET_CPU=generic -DCONFIG_MULTITHREAD=0 -DCONFIG_RUNTIME_CPU_DETECT=0) ;;
  esac
  cmake_build -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TESTS=0 -DENABLE_TOOLS=0 \
    ${cpu[@]+"${cpu[@]}"}
}
