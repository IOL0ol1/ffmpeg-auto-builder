# x265: HEVC encoder (GPL). FFmpeg: --enable-libx265 (requires --enable-gpl). 8-bit build.
DEP_VERSION=4.1
DEP_URL="https://bitbucket.org/multicoreware/x265_git/downloads/x265_${DEP_VERSION}.tar.gz"
DEP_SHA256=a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29

dep_build() {
  fetch_source
  cd source
  # The assembly does not build with llvm-mingw for 32-bit x86 or ARM64 Windows.
  local asm=ON
  [[ "$TARGET_PLATFORM" == "windows" && "$TARGET_ARCH" != "x86_64" ]] && asm=OFF
  cmake_build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ASSEMBLY="$asm"
}
