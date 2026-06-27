#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"

require_env SOURCE_REPOSITORY
require_env SOURCE_PAT
require_env TARGET_PLATFORM
require_env TARGET_ARCH
require_env PACKAGE_FORMAT
require_env CONFIGURE_OPTIONS
require_env RELEASE_TAG

clean_repository_url="$(normalize_repository_url "$SOURCE_REPOSITORY")"
authenticated_repository_url="$(build_authenticated_repository_url "$clean_repository_url" "$SOURCE_PAT")"
sanitize_configure_options "$CONFIGURE_OPTIONS"

# Auto-inject cross-compilation flags for Linux when a cross-prefix is provided.
# These are prepended so that any user-supplied flags (e.g. a custom --cross-prefix) win.
if [[ "$TARGET_PLATFORM" == "linux" && -n "${CROSS_PREFIX:-}" ]]; then
  case "$TARGET_ARCH" in
    x86)   ffmpeg_arch="x86" ;;
    armv7) ffmpeg_arch="arm" ;;
    arm64) ffmpeg_arch="aarch64" ;;
    *)     ffmpeg_arch="$TARGET_ARCH" ;;
  esac
  SANITIZED_CONFIGURE_ARGS=(
    "--arch=${ffmpeg_arch}"
    "--target-os=linux"
    "--enable-cross-compile"
    "--cross-prefix=${CROSS_PREFIX}"
    "${SANITIZED_CONFIGURE_ARGS[@]}"
  )
fi

work_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ffmpeg-build-${RELEASE_TAG}"
source_dir="$work_root/source"
install_root="$work_root/install"
dist_root="$repo_root/dist"
package_root="$dist_root/packages"

cleanup() {
  if [[ -d "$source_dir/.git" ]]; then
    git -C "$source_dir" remote set-url origin "$clean_repository_url" >/dev/null 2>&1 || true
  fi

  rm -f "$HOME/.git-credentials"
}

trap cleanup EXIT

rm -rf "$work_root" "$dist_root"
mkdir -p "$source_dir" "$install_root" "$package_root"

if [[ -n "${SOURCE_REF:-}" ]]; then
  [[ "$SOURCE_REF" =~ $SAFE_TOKEN_PATTERN ]] || fail "Unsafe SOURCE_REF: ${SOURCE_REF}"
  # Try shallow clone for a branch or tag; fall back to full clone for a commit SHA
  git clone --depth 1 --branch "$SOURCE_REF" "$authenticated_repository_url" "$source_dir" \
    || { git clone "$authenticated_repository_url" "$source_dir"; git -C "$source_dir" checkout "$SOURCE_REF"; }
else
  git clone --depth 1 "$authenticated_repository_url" "$source_dir"
fi
git -C "$source_dir" remote set-url origin "$clean_repository_url"

pushd "$source_dir" >/dev/null
./configure --prefix="$install_root" "${SANITIZED_CONFIGURE_ARGS[@]}"
make -j"$(cpu_count)"
make install
popd >/dev/null

package_name="ffmpeg-${TARGET_PLATFORM}-${TARGET_ARCH}-${RELEASE_TAG}"
case "$PACKAGE_FORMAT" in
  tar.gz)
    tar -C "$install_root" -czf "$package_root/${package_name}.tar.gz" .
    ;;
  zip)
    if command -v zip >/dev/null 2>&1; then
      (
        cd "$install_root"
        zip -qr "$package_root/${package_name}.zip" .
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
