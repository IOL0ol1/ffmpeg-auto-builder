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

# Cross-compilation flags for Linux when a cross-prefix is provided.
if [[ "$TARGET_PLATFORM" == "linux" && -n "${CROSS_PREFIX:-}" ]]; then
  case "$TARGET_ARCH" in
    x86)   ffmpeg_arch="x86" ;;
    armv7) ffmpeg_arch="arm" ;;
    arm64) ffmpeg_arch="aarch64" ;;
    *)     ffmpeg_arch="$TARGET_ARCH" ;;
  esac
  injected_args+=(
    "--arch=${ffmpeg_arch}"
    "--target-os=linux"
    "--enable-cross-compile"
    "--cross-prefix=${CROSS_PREFIX}"
  )
fi

# Route compilation through ccache when available.
if command -v ccache >/dev/null 2>&1; then
  if [[ "$TARGET_PLATFORM" == "macos" || "${MSYSTEM:-}" == CLANG* ]]; then
    base_cc="clang"
  else
    base_cc="${CROSS_PREFIX:-}gcc"
  fi
  injected_args+=("--cc=ccache ${base_cc}")
  ccache --zero-stats >/dev/null 2>&1 || true
fi

SANITIZED_CONFIGURE_ARGS=("${injected_args[@]}" "${SANITIZED_CONFIGURE_ARGS[@]}")

work_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ffmpeg-build-${RELEASE_TAG}"
if command -v cygpath >/dev/null 2>&1; then
  # Windows runners report RUNNER_TEMP as "D:\a\_temp"; configure needs a POSIX path.
  work_root="$(cygpath -u "$work_root")"
fi
install_root="$work_root/install"
dist_root="$repo_root/dist"
package_root="$dist_root/packages"

rm -rf "$work_root" "$dist_root"
mkdir -p "$install_root" "$package_root"

pushd "$source_dir" >/dev/null
./configure --prefix="$install_root" "${SANITIZED_CONFIGURE_ARGS[@]}"
make -j"$(cpu_count)"
make install
popd >/dev/null

if command -v ccache >/dev/null 2>&1; then
  ccache --show-stats || true
fi

# ── Make the install tree relocatable ────────────────────────────────────────

shopt -s nullglob

# Rewrite absolute install paths in pkg-config files to be relative to the .pc file.
fix_pkgconfig() {
  local pc
  for pc in "$install_root"/lib/pkgconfig/*.pc; do
    sed -i.bak \
      -e "s|^prefix=${install_root}\$|prefix=\${pcfiledir}/../..|" \
      -e "s|${install_root}|\${prefix}|g" \
      "$pc"
    rm -f "$pc.bak"
  done
}

# Point binaries at ../lib and shared libraries at their own directory.
fix_linux_rpath() {
  local libs=("$install_root"/lib/*.so*)
  [[ "${#libs[@]}" -gt 0 ]] || return 0

  local f
  for f in "$install_root"/bin/*; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      patchelf --set-rpath '$ORIGIN/../lib' "$f" 2>/dev/null || true
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

  local f dep rpath
  for f in "$install_root"/bin/* "${libs[@]}"; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    lipo -info "$f" >/dev/null 2>&1 || continue

    if [[ "$f" == *.dylib ]]; then
      install_name_tool -id "@rpath/$(basename "$f")" "$f"
      rpath='@loader_path'
    else
      rpath='@loader_path/../lib'
    fi

    while IFS= read -r dep; do
      install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f"
    done < <(otool -L "$f" | awk -v p="$lib_dir/" 'NR > 1 && index($1, p) == 1 { print $1 }')

    install_name_tool -add_rpath "$rpath" "$f" 2>/dev/null || true
    codesign --force --sign - "$f" >/dev/null 2>&1 || true
  done
}

# Copy MinGW runtime DLLs (libwinpthread, libgcc, ...) next to the executables.
bundle_windows_runtime() {
  [[ -n "${MINGW_PREFIX:-}" ]] || return 0

  local f dll
  for f in "$install_root"/bin/*.exe "$install_root"/bin/*.dll; do
    while IFS= read -r dll; do
      case "$dll" in
        "$MINGW_PREFIX"/bin/*)
          [[ -e "$install_root/bin/$(basename "$dll")" ]] || cp "$dll" "$install_root/bin/"
          ;;
      esac
    done < <(ldd "$f" 2>/dev/null | awk '{ print $3 }' || true)
  done
}

fix_pkgconfig
case "$TARGET_PLATFORM" in
  linux)   fix_linux_rpath ;;
  macos)   fix_macos_install_names ;;
  windows) bundle_windows_runtime ;;
esac

# ── Smoke test (native builds only) ──────────────────────────────────────────

ffmpeg_bin="$install_root/bin/ffmpeg"
if [[ "$TARGET_PLATFORM" == "windows" ]]; then
  ffmpeg_bin+=".exe"
fi
if [[ -z "${CROSS_PREFIX:-}" && -x "$ffmpeg_bin" ]]; then
  version_output="$("$ffmpeg_bin" -hide_banner -version)" || fail "Smoke test failed: $ffmpeg_bin -version"
  printf 'Smoke test OK: %s\n' "${version_output%%$'\n'*}"
fi

# ── Build metadata ───────────────────────────────────────────────────────────

compiler_version="$(${base_cc:-cc} --version 2>/dev/null | head -n 1 || true)"
{
  echo "release_tag: ${RELEASE_TAG}"
  echo "source_repository: ${SOURCE_REPOSITORY:-}"
  echo "source_ref: ${SOURCE_REF:-<default branch>}"
  echo "source_commit: ${SOURCE_COMMIT:-}"
  echo "platform: ${TARGET_PLATFORM}"
  echo "arch: ${TARGET_ARCH}"
  echo "compiler: ${compiler_version}"
  echo "built_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "configure: ${SANITIZED_CONFIGURE_ARGS[*]}"
} >"$install_root/BUILDINFO.txt"

# ── Package ──────────────────────────────────────────────────────────────────

# RELEASE_TAG is "ffmpeg-<platform>-<arch>-<build id>"; keep only the build id to avoid repeating it.
package_name="ffmpeg-${TARGET_PLATFORM}-${TARGET_ARCH}-${RELEASE_TAG#ffmpeg-*-*-}"
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
