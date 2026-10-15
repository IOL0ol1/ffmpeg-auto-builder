#!/usr/bin/env bash
# Build the third-party libraries in deps/*.sh as static, position-independent libraries
# into $DEPS_PREFIX for one target, so FFmpeg can link them into static executables or
# shared libraries.
#
# Environment:
#   TARGET_PLATFORM  linux | macos | windows
#   TARGET_ARCH      x86_64 | x86 | arm64
#   DEPS_PREFIX      install prefix for the libraries
#   DEPS_WORK        scratch directory for sources and builds (default: $RUNNER_TEMP/deps-work)
#   LLVM_MINGW       llvm-mingw toolchain root (windows only; see scripts/install-deps.sh)
#
# Each deps/NN-name.sh sets DEP_VERSION, DEP_URL, DEP_SHA256 and defines dep_build;
# DEP_PLATFORMS (default: all) limits the targets it is built for.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"
source "$script_dir/toolchain.sh"

require_env DEPS_PREFIX
DEPS_WORK="${DEPS_WORK:-${RUNNER_TEMP:-/tmp}/deps-work}"
mkdir -p "$DEPS_PREFIX" "$DEPS_WORK/sources"

setup_toolchain

# ── Helpers for deps/*.sh ────────────────────────────────────────────────────

# Download DEP_URL (verified against DEP_SHA256), unpack it and cd into the source tree.
fetch_source() {
  local archive="$DEPS_WORK/sources/${DEP_NAME}-${DEP_VERSION}.${DEP_URL##*.}"
  if [[ ! -f "$archive" ]]; then
    curl -fsSL --retry 3 -o "$archive.part" "$DEP_URL"
    mv "$archive.part" "$archive"
  fi
  echo "${DEP_SHA256}  ${archive}" | sha256sum -c - >/dev/null || fail "Checksum mismatch for $DEP_URL"

  local src="$DEPS_WORK/build/$DEP_NAME"
  rm -rf "$src"
  mkdir -p "$src"
  tar -xf "$archive" -C "$src" --strip-components=1
  cd "$src"
}

# Old autotools tarballs ship config.sub / config.guess that predate targets such as
# arm64-apple-darwin or aarch64-w64-mingw32; use the copies from the installed automake.
update_config_scripts() {
  local libdir
  libdir="$(automake --print-libdir)"
  find . -name config.sub -exec cp "$libdir/config.sub" {} \;
  find . -name config.guess -exec cp "$libdir/config.guess" {} \;
}

autotools_build() {
  ./configure --prefix="$DEPS_PREFIX" --libdir="$DEPS_PREFIX/lib" \
    --enable-static --disable-shared --with-pic ${AUTOTOOLS_HOST_ARGS[@]+"${AUTOTOOLS_HOST_ARGS[@]}"} "$@"
  make -j"$(cpu_count)"
  make install
}

cmake_build() {
  cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    ${CMAKE_TOOLCHAIN_ARGS[@]+"${CMAKE_TOOLCHAIN_ARGS[@]}"} "$@"
  cmake --build build -j "$(cpu_count)"
  cmake --install build
}

meson_build() {
  meson setup build \
    --prefix="$DEPS_PREFIX" --libdir=lib \
    --buildtype=release --default-library=static -Db_staticpic=true \
    ${MESON_CROSS_ARGS[@]+"${MESON_CROSS_ARGS[@]}"} "$@"
  ninja -C build -j "$(cpu_count)"
  ninja -C build install
}

# ── Build ────────────────────────────────────────────────────────────────────

target_key="${TARGET_PLATFORM}/${TARGET_ARCH}"
built=()

# Tell the workflow whether the prefix changed, also when a later library fails, so the
# libraries finished so far can be cached and skipped on the next run.
report_changes() {
  [[ -z "${GITHUB_OUTPUT:-}" ]] || echo "changed=$([[ ${#built[@]} -gt 0 ]] && echo true || echo false)" >>"$GITHUB_OUTPUT"
}
trap report_changes EXIT
for dep in "$repo_root"/deps/[0-9]*.sh; do
  DEP_NAME="$(basename "$dep" .sh)"
  DEP_NAME="${DEP_NAME#*-}"
  DEP_PLATFORMS="linux/x86_64 linux/arm64 linux/x86 linux/armv7 macos/x86_64 macos/arm64 windows/x86_64 windows/x86 windows/arm64"
  unset -f dep_build
  source "$dep"

  [[ " $DEP_PLATFORMS " == *" $target_key "* ]] || { echo "Skipping $DEP_NAME on $target_key"; continue; }

  # The stamp covers the recipe itself, so editing deps/<name>.sh rebuilds that library.
  stamp="$DEPS_PREFIX/.stamps/${DEP_NAME}-${DEP_VERSION}-$(sha256sum "$dep" | cut -c1-12)"
  if [[ -f "$stamp" ]]; then
    echo "Up to date: $DEP_NAME $DEP_VERSION"
    continue
  fi

  echo "::group::Build $DEP_NAME $DEP_VERSION"
  (dep_build)
  echo "::endgroup::"
  mkdir -p "$DEPS_PREFIX/.stamps"
  touch "$stamp"
  built+=("$DEP_NAME")
done

# Some projects install shared libraries or libtool archives regardless; keep static only.
find "$DEPS_PREFIX/lib" -maxdepth 1 \( -name '*.la' -o -name '*.so*' -o -name '*.dylib' -o -name '*.dll.a' \) -delete
find "$DEPS_PREFIX/bin" -maxdepth 1 -name '*.dll' -delete 2>/dev/null || true

printf 'Built: %s\n' "${built[*]:-(nothing, all cached)}"
