# x265: HEVC encoder (GPL). FFmpeg: --enable-libx265 (requires --enable-gpl). 8-bit build.
DEP_VERSION=4.1
DEP_URL="https://bitbucket.org/multicoreware/x265_git/downloads/x265_${DEP_VERSION}.tar.gz"
DEP_SHA256=a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29

dep_build() {
  fetch_source
  cd source
  # CMake 4 rejects the OLD policies x265 asks for; use NEW and keep recognizing AppleClang.
  sed -i.bak \
    -e 's/cmake_policy(SET CMP0025 OLD)/cmake_policy(SET CMP0025 NEW)/' \
    -e 's/cmake_policy(SET CMP0054 OLD)/cmake_policy(SET CMP0054 NEW)/' \
    -e 's/STREQUAL "Clang"/MATCHES "Clang"/g' \
    CMakeLists.txt
  # The assembly does not build with llvm-mingw for 32-bit x86 or ARM64 Windows.
  local asm=ON
  [[ "$TARGET_PLATFORM" == "windows" && "$TARGET_ARCH" != "x86_64" ]] && asm=OFF
  cmake_build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ASSEMBLY="$asm"
  # x265 prefixes every implicit compiler library with -l; llvm-mingw reports
  # "-l:libunwind.a", which turns into the invalid "-l-l:libunwind.a".
  sed -i.bak 's/-l-l:/-l:/g' "$DEPS_PREFIX/lib/pkgconfig/x265.pc"
  rm -f "$DEPS_PREFIX/lib/pkgconfig/x265.pc.bak"
}
