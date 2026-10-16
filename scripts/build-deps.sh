#!/usr/bin/env bash
# Build the third-party libraries in deps/*.sh for one target into $DEPS_PREFIX: static,
# position-independent libraries that FFmpeg links in (DEPS_LINKAGE=static, the default),
# or shared libraries shipped next to FFmpeg's (DEPS_LINKAGE=shared).
#
# Environment:
#   TARGET_PLATFORM  a platform of docs/targets.json
#   TARGET_ARCH      one of its architectures
#   DEPS_PREFIX      install prefix for the libraries
#   DEPS_LINKAGE     static | shared
#   DEPS_WORK        scratch directory for sources and builds (default: $RUNNER_TEMP/deps-work)
#   LLVM_MINGW       llvm-mingw toolchain root (windows only; see scripts/platforms/windows.sh)
#
# Each deps/NN-name.sh sets DEP_VERSION, DEP_URL, DEP_SHA256 and defines dep_build. DEP_FEATURE
# (default: the recipe name; empty: always built) is the library toggle of docs/configure.js
# it belongs to; a target skips the recipes whose toggle docs/targets.json lists as unavailable.
# DEP_SHARED=no keeps a library static in shared mode when it cannot build shared there.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"
source "$script_dir/toolchain.sh"

require_env DEPS_PREFIX
DEPS_LINKAGE="${DEPS_LINKAGE:-static}"
DEPS_WORK="${DEPS_WORK:-${RUNNER_TEMP:-/tmp}/deps-work}"
mkdir -p "$DEPS_PREFIX" "$DEPS_WORK/sources"

setup_toolchain

# ── Helpers for deps/*.sh ────────────────────────────────────────────────────

# True when the current recipe builds a shared library.
dep_shared() {
  [[ "$DEPS_LINKAGE" == shared && "${DEP_SHARED:-yes}" != no ]]
}

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
  local kind=(--enable-static --disable-shared --with-pic)
  dep_shared && kind=(--disable-static --enable-shared)
  ./configure --prefix="$DEPS_PREFIX" --libdir="$DEPS_PREFIX/lib" \
    "${kind[@]}" ${AUTOTOOLS_HOST_ARGS[@]+"${AUTOTOOLS_HOST_ARGS[@]}"} "$@"
  make -j"$(cpu_count)"
  make install
}

cmake_build() {
  cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
    -DBUILD_SHARED_LIBS="$(dep_shared && echo ON || echo OFF)" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    ${CMAKE_TOOLCHAIN_ARGS[@]+"${CMAKE_TOOLCHAIN_ARGS[@]}"} "$@"
  cmake --build build -j "$(cpu_count)"
  cmake --install build
}

meson_build() {
  meson setup build \
    --prefix="$DEPS_PREFIX" --libdir=lib \
    --buildtype=release --default-library="$(dep_shared && echo shared || echo static)" -Db_staticpic=true \
    ${MESON_CROSS_ARGS[@]+"${MESON_CROSS_ARGS[@]}"} "$@"
  ninja -C build -j "$(cpu_count)"
  ninja -C build install
}

# ── Build ────────────────────────────────────────────────────────────────────

target_key="${TARGET_PLATFORM}/${TARGET_ARCH}"
unavailable=" $(python3 -I "$script_dir/targets.py" unavailable "$TARGET_PLATFORM" "$TARGET_ARCH" | tr -d '\r') "
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
  DEP_FEATURE="$DEP_NAME"
  DEP_SHARED=yes
  unset -f dep_build
  source "$dep"

  if [[ -n "$DEP_FEATURE" && "$unavailable" == *" $DEP_FEATURE "* ]]; then
    echo "Skipping $DEP_NAME: $DEP_FEATURE is not available on $target_key"
    continue
  fi

  # The stamp covers the recipe itself, so editing deps/<name>.sh rebuilds that library.
  stamp="$DEPS_PREFIX/.stamps/${DEP_NAME}-${DEP_VERSION}-$(sha256sum "$dep" | cut -c1-12)"
  if [[ -f "$stamp" ]]; then
    echo "Up to date: $DEP_NAME $DEP_VERSION"
    continue
  fi

  echo "::group::Build $DEP_NAME $DEP_VERSION"
  touch "$DEPS_WORK/.build-start"
  (dep_build)
  # A library kept static in shared mode may have been shared in a cached prefix; remove
  # those files, so the linker takes the new static library.
  if [[ "$DEPS_LINKAGE" == shared ]] && ! dep_shared; then
    while IFS= read -r archive; do
      base="${archive%.a}"
      rm -f "$base".so* "$base".*dylib "$base.dylib" "$base.dll.a"
    done < <(find "$DEPS_PREFIX/lib" -maxdepth 1 -name 'lib*.a' ! -name '*.dll.a' -newer "$DEPS_WORK/.build-start")
  fi
  echo "::endgroup::"
  mkdir -p "$DEPS_PREFIX/.stamps"
  touch "$stamp"
  built+=("$DEP_NAME")
done

find "$DEPS_PREFIX/lib" -maxdepth 1 -name '*.la' -delete
if [[ "$DEPS_LINKAGE" == static ]]; then
  # Some projects install shared libraries regardless; keep static only.
  find "$DEPS_PREFIX/lib" -maxdepth 1 \( -name '*.so*' -o -name '*.dylib' -o -name '*.dll.a' \) -delete
  find "$DEPS_PREFIX/bin" -maxdepth 1 -name '*.dll' -delete 2>/dev/null || true
else
  # And static ones next to the shared ones; the linker must not pick those.
  for archive in "$DEPS_PREFIX"/lib/lib*.a; do
    [[ "$archive" != *.dll.a ]] || continue
    base="${archive%.a}"
    if compgen -G "$base.so*" >/dev/null || compgen -G "$base.*dylib" >/dev/null || [[ -e "$base.dll.a" ]]; then
      rm -f "$archive"
    fi
  done
fi

printf 'Built: %s\n' "${built[*]:-(nothing, all cached)}"
