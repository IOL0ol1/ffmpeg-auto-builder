#!/usr/bin/env bash
# Configure, build and package an FFmpeg source tree that the workflow has already checked out.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"

require_env TARGET_PLATFORM
require_env TARGET_ARCH
require_env PACKAGE_FORMAT
require_env CONFIGURE_OPTIONS
require_env RELEASE_TAG

validate_release_tag "$RELEASE_TAG"
sanitize_configure_options "$CONFIGURE_OPTIONS"

source_dir="${SOURCE_DIR:-$repo_root/ffmpeg-src}"
[[ -x "$source_dir/configure" ]] || fail "FFmpeg source tree not found at $source_dir"

# Flags injected here are prepended so that any user-supplied flags (which come later) win.
injected_args=()

# Targets with third-party libraries: toolchain, cross-compilation and pkg-config setup
# shared with scripts/build-deps.sh (libraries in $DEPS_PREFIX, linked statically).
if [[ -n "${DEPS_PREFIX:-}" ]]; then
  source "$script_dir/toolchain.sh"
  setup_toolchain
  injected_args+=("${FFMPEG_TOOLCHAIN_ARGS[@]}")
  # Static C++ libraries (x265, zimg, HarfBuzz, ...) need the C++ runtime at link time, and
  # glibc 2.28 keeps libm and libpthread separate, and soxr / x265 do not list them.
  case "$TARGET_PLATFORM" in
    linux)   injected_args+=("--extra-libs=-lstdc++" "--extra-libs=-lm" "--extra-libs=-lpthread") ;;
    # The NDK's static libc++; bionic has no separate libpthread.
    android) injected_args+=("--extra-libs=-lc++_static" "--extra-libs=-lc++abi" "--extra-libs=-lm") ;;
    freebsd) injected_args+=("--extra-libs=-lc++" "--extra-libs=-lm" "--extra-libs=-lpthread") ;;
    # em++ links the C++ runtime (see scripts/platforms/wasm.sh).
    wasm)    ;;
    *)       injected_args+=("--extra-libs=-lc++") ;;
  esac
  case "$TARGET_PLATFORM/$TARGET_ARCH" in
    # The 32-bit x86 assembly needs text relocations, which Android rejects.
    android/x86) injected_args+=("--disable-asm") ;;
    # Mac Catalyst has neither NSOpenGL (Core Image filters) nor Secure Transport.
    maccatalyst/*) injected_args+=("--disable-coreimage" "--disable-securetransport") ;;
    # visionOS has no AVFoundation capture devices.
    visionos/*) injected_args+=("--disable-indev=avfoundation") ;;
    # The MIPS FPU inline assembly uses odd float registers, which the o32 ABI forbids.
    linux/mipsel) injected_args+=("--disable-mipsfpu") ;;
  esac
  # On Intel Macs Homebrew lives in /usr/local, which the compiler searches by default, so
  # link-test autodetection would pick up its liblzma / libX11 and tie the binaries to it.
  if [[ "$TARGET_PLATFORM" == "macos" ]]; then
    injected_args+=("--disable-lzma" "--disable-xlib")
  fi
fi

# Route compilation through ccache when available.
if [[ -n "${DEPS_PREFIX:-}" ]]; then
  base_cc="$CC"
elif [[ "$TARGET_PLATFORM" == "macos" ]]; then
  base_cc="clang"
else
  base_cc="gcc"
fi
if command -v ccache >/dev/null 2>&1; then
  injected_args+=("--cc=ccache ${base_cc}")
  ccache --zero-stats >/dev/null 2>&1 || true
fi

SANITIZED_CONFIGURE_ARGS=("${injected_args[@]}" "${SANITIZED_CONFIGURE_ARGS[@]}")

work_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ffmpeg-build-${RELEASE_TAG}"
install_root="$work_root/install"
dist_root="$repo_root/dist"
package_root="$dist_root/packages"

rm -rf "$work_root" "$dist_root"
mkdir -p "$install_root" "$package_root"

pushd "$source_dir" >/dev/null
# configure only reports which check failed; the reason is in ffbuild/config.log.
./configure --prefix="$install_root" "${SANITIZED_CONFIGURE_ARGS[@]}" || {
  tail -n 60 ffbuild/config.log
  exit 1
}
make -j"$(cpu_count)"
make install
popd >/dev/null

if command -v ccache >/dev/null 2>&1; then
  ccache --show-stats || true
fi

# ── Make the install tree relocatable ────────────────────────────────────────

shopt -s nullglob

# Static FFmpeg libraries still need the third-party ones they were built against; ship
# them next to libavcodec.a etc. so that linking with the package works on its own.
bundle_static_deps() {
  local libs=("$install_root"/lib/libavutil.a)
  [[ "${#libs[@]}" -gt 0 && -n "${DEPS_PREFIX:-}" ]] || return 0
  local lib
  for lib in "$DEPS_PREFIX"/lib/*.a; do
    [[ -e "$install_root/lib/$(basename "$lib")" ]] || cp "$lib" "$install_root/lib/"
  done
}

# Rewrite absolute install paths in pkg-config files to be relative to the .pc file; the
# third-party libraries are in the same lib/ (bundle_static_deps) or linked in already.
fix_pkgconfig() {
  local pc
  for pc in "$install_root"/lib/pkgconfig/*.pc; do
    sed -i.bak \
      -e "s|^prefix=${install_root}\$|prefix=\${pcfiledir}/../..|" \
      -e "s|${install_root}|\${prefix}|g" \
      -e "s| -L${DEPS_PREFIX:-/nonexistent}/lib||g" \
      "$pc"
    rm -f "$pc.bak"
  done
}

# Point binaries at ../lib (install tree) and their own directory (the flattened
# runtimes/<rid>/native layout of the NuGet package); libraries at their own directory.
fix_linux_rpath() {
  local libs=("$install_root"/lib/*.so*)
  [[ "${#libs[@]}" -gt 0 ]] || return 0

  local f
  for f in "$install_root"/bin/*; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      patchelf --set-rpath '$ORIGIN/../lib:$ORIGIN' "$f" 2>/dev/null || true
    fi
  done
  for f in "${libs[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      patchelf --set-rpath '$ORIGIN' "$f"
    fi
  done
}

# Replace absolute dylib install names with @rpath references.
fix_macos_install_names() {
  local lib_dir="$install_root/lib"
  local libs=("$lib_dir"/*.dylib)
  [[ "${#libs[@]}" -gt 0 ]] || return 0

  local f dep rpath rpaths
  for f in "$install_root"/bin/* "${libs[@]}"; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    lipo -info "$f" >/dev/null 2>&1 || continue

    if [[ "$f" == *.dylib ]]; then
      # Keep FFmpeg's major-version name (libavcodec.63.dylib), not the file's full version.
      install_name_tool -id "@rpath/$(basename "$(otool -D "$f" | tail -n 1)")" "$f"
      rpaths=('@loader_path')
    else
      # ../lib for the install tree, the own directory for the NuGet runtimes layout.
      rpaths=('@loader_path/../lib' '@loader_path')
    fi

    while IFS= read -r dep; do
      install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f"
    done < <(otool -L "$f" | awk -v p="$lib_dir/" 'NR > 1 && index($1, p) == 1 { print $1 }')

    for rpath in "${rpaths[@]}"; do
      install_name_tool -add_rpath "$rpath" "$f" 2>/dev/null || true
    done
    codesign --force --sign - "$f" >/dev/null 2>&1 || true
  done
}

# Copy toolchain runtime DLLs (libc++, libunwind, ...) that the binaries still import next
# to them. The runtime is linked statically, so normally there is nothing to copy.
bundle_windows_runtime() {
  [[ -n "${TOOLCHAIN_BIN:-}" ]] || return 0

  local f dll
  for f in "$install_root"/bin/*.exe "$install_root"/bin/*.dll; do
    while IFS= read -r dll; do
      if [[ -f "$TOOLCHAIN_BIN/$dll" && ! -e "$install_root/bin/$dll" ]]; then
        cp "$TOOLCHAIN_BIN/$dll" "$install_root/bin/"
      fi
    done < <(llvm-objdump -p "$f" 2>/dev/null | awk '/DLL Name:/ { print $3 }' || true)
  done
}

# Shared Windows builds link through the import libraries avcodec.lib etc., which FFmpeg
# installs next to the DLLs; move them to lib/ and drop the MinGW-only libavcodec.dll.a.
fix_windows_import_libs() {
  local implib
  for implib in "$install_root"/bin/*.lib; do
    mv "$implib" "$install_root/lib/"
  done
  rm -f "$install_root"/lib/lib*.dll.a
}

bundle_static_deps
fix_pkgconfig
case "$TARGET_PLATFORM" in
  linux | freebsd)     fix_linux_rpath ;;
  macos | maccatalyst) fix_macos_install_names ;;
  windows)             bundle_windows_runtime; fix_windows_import_libs ;;
esac

# ── Smoke test (wherever the build host can run the result) ─────────────────

# TARGET_RUNNER comes from toolchain.sh: empty for native, "qemu-arm ..." for armv7 and
# "none" for Windows, which is cross-compiled and cannot run on Linux.
ffmpeg_bin="$install_root/bin/ffmpeg"
if [[ "${TARGET_RUNNER:-}" != "none" && -x "$ffmpeg_bin" ]]; then
  read -r -a runner <<<"${TARGET_RUNNER:-}"
  version_output="$(${runner[@]+"${runner[@]}"} "$ffmpeg_bin" -hide_banner -version)" \
    || fail "Smoke test failed: $ffmpeg_bin -version"
  printf 'Smoke test OK: %s\n' "${version_output%%$'\n'*}"
fi

# ── Build metadata ───────────────────────────────────────────────────────────

compiler_version="$(${base_cc:-cc} --version 2>/dev/null | head -n 1 || true)"
{
  echo "release_tag: ${RELEASE_TAG}"
  echo "source_repository: ${SOURCE_REPOSITORY:-}"
  echo "source_ref: ${SOURCE_REF:-<default branch>}"
  echo "source_commit: ${SOURCE_COMMIT:-}"
  echo "ffmpeg_version: $(head -n 1 "$source_dir/RELEASE" 2>/dev/null || true)"
  echo "platform: ${TARGET_PLATFORM}"
  echo "arch: ${TARGET_ARCH}"
  echo "compiler: ${compiler_version}"
  echo "built_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "configure: ${SANITIZED_CONFIGURE_ARGS[*]}"
} >"$install_root/BUILDINFO.txt"

# ── Package ──────────────────────────────────────────────────────────────────

# ffmpeg-<platform>-<arch>-<license>-<build id>; RELEASE_TAG is "ffmpeg-<platform>-<arch>-<build id>".
package_name="ffmpeg-${TARGET_PLATFORM}-${TARGET_ARCH}-$(license_id "${SANITIZED_CONFIGURE_ARGS[@]}")-${RELEASE_TAG#ffmpeg-*-*-}"
case "$PACKAGE_FORMAT" in
  tar.gz)
    tar -C "$install_root" -czf "$package_root/${package_name}.tar.gz" .
    ;;
  zip)
    if command -v zip >/dev/null 2>&1; then
      (
        cd "$install_root"
        zip -qry "$package_root/${package_name}.zip" .
      )
    else
      python3 - "$install_root" "$package_root/${package_name}.zip" <<'PY'
import pathlib
import sys
import zipfile

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in source.rglob("*"):
        archive.write(path, path.relative_to(source))
PY
    fi
    ;;
  *)
    fail "Unsupported package format: $PACKAGE_FORMAT"
    ;;
esac

printf 'Package created in %s\n' "$package_root"
