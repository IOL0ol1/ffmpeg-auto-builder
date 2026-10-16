# WebAssembly target, sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain): cross-compiled on Ubuntu with Emscripten into
# static libraries for Emscripten projects. Single-threaded: WebAssembly threads need
# SharedArrayBuffer, which browsers only offer to cross-origin isolated pages.

EMSDK_VERSION=6.0.10
EMSDK_COMMIT=a2b92777574c2feda07994cd4f1079a3dfc151f8

platform_install() {
  sudo apt-get update
  sudo apt-get install -y pkg-config ccache zip unzip automake autoconf libtool cmake pipx
  install_python_build_tools

  local emsdk="${RUNNER_TOOL_CACHE:-/opt}/emsdk-$EMSDK_VERSION"
  if [[ ! -x "$emsdk/upstream/emscripten/emcc" ]]; then
    rm -rf "$emsdk"
    git clone --quiet https://github.com/emscripten-core/emsdk.git "$emsdk"
    git -C "$emsdk" checkout --quiet "$EMSDK_COMMIT"
    "$emsdk/emsdk" install "$EMSDK_VERSION"
    "$emsdk/emsdk" activate "$EMSDK_VERSION"
  fi
  export_env EMSDK "$emsdk"
}

platform_toolchain() {
  require_env EMSDK
  # emsdk_env.sh puts emcc, node and the LLVM tools on PATH (and is not written for set -u).
  set +u
  # shellcheck disable=SC1091
  EMSDK_QUIET=1 source "$EMSDK/emsdk_env.sh" >/dev/null
  set -u
  local em="$EMSDK/upstream/emscripten"
  export CC=emcc CXX=em++ AR=emar RANLIB=emranlib NM=emnm STRIP=llvm-strip
  TARGET_RUNNER="none"
  AUTOTOOLS_HOST_ARGS=(--host=wasm32-unknown-emscripten)
  write_cross_files Emscripten wasm32 wasm32 "$CC" "$CXX" "$AR" "$STRIP"
  # CMake projects use Emscripten's own toolchain file.
  CMAKE_TOOLCHAIN_ARGS=("-DCMAKE_TOOLCHAIN_FILE=$em/cmake/Modules/Platform/Emscripten.cmake")
  FFMPEG_TOOLCHAIN_ARGS=(
    "--target-os=none"
    "--arch=wasm"
    "--enable-cross-compile"
    "--cc=$CC"
    "--cxx=$CXX"
    # em++ links libc++ for the C++ libraries (zimg, ...).
    "--ld=$CXX"
    "--ar=$AR"
    "--ranlib=$RANLIB"
    "--nm=$NM"
    "--disable-stripping"
    "--disable-pthreads"
  )
}
