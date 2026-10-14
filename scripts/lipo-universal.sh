#!/usr/bin/env bash
# Merge an x86_64 and arm64 macOS FFmpeg install tree into a universal (fat) binary package.
# Expected environment variables: PACKAGE_FORMAT, RELEASE_TAG
# Expected directory layout (relative to repo root):
#   artifacts/x86_64/   – contains the x86_64 package file (tar.gz or zip)
#   artifacts/arm64/    – contains the arm64 package file (tar.gz or zip)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"

require_env PACKAGE_FORMAT
require_env RELEASE_TAG
validate_release_tag "$RELEASE_TAG"

x86_artifacts="${repo_root}/artifacts/x86_64"
arm64_artifacts="${repo_root}/artifacts/arm64"
x86_install="/tmp/lipo-x86_64"
arm64_install="/tmp/lipo-arm64"
universal_install="/tmp/lipo-universal"
dist_root="${repo_root}/dist"
package_root="${dist_root}/packages"

rm -rf "$dist_root" "$x86_install" "$arm64_install" "$universal_install"
mkdir -p "$package_root" "$x86_install" "$arm64_install" "$universal_install"

# ── Extract packages ──────────────────────────────────────────────────────────

extract_package() {
  local pkg_dir="$1"
  local dest="$2"
  local pkg
  pkg="$(find "$pkg_dir" -maxdepth 1 -type f | head -n 1)"
  [[ -n "$pkg" ]] || fail "No artifact found in $pkg_dir"
  case "$pkg" in
    *.tar.gz) tar -xzf "$pkg" -C "$dest" ;;
    *.zip)    unzip -q "$pkg" -d "$dest" ;;  # unzip keeps exec bits and symlinks
    *)        fail "Unknown package format: $pkg" ;;
  esac
}

extract_package "$x86_artifacts" "$x86_install"
extract_package "$arm64_artifacts" "$arm64_install"

# ── Build universal tree ──────────────────────────────────────────────────────

# Start with a complete copy of the x86_64 tree (preserves symlinks, dirs, etc.)
cp -RP "${x86_install}/." "${universal_install}/"

# For each regular file in the arm64 tree, lipo-merge Mach-O binaries; copy others.
while IFS= read -r arm_file; do
  rel="${arm_file#"${arm64_install}/"}"
  x86_file="${x86_install}/${rel}"
  out_file="${universal_install}/${rel}"
  mkdir -p "$(dirname "$out_file")"

  # lipo -info accepts Mach-O executables, dylibs and static (.a) archives alike.
  if [[ -f "$x86_file" ]] && lipo -info "$x86_file" >/dev/null 2>&1; then
    lipo -create "$x86_file" "$arm_file" -output "$out_file" \
      || { echo "lipo failed for $rel, keeping x86_64 copy" >&2; cp "$x86_file" "$out_file"; }
  elif [[ ! -e "$out_file" ]]; then
    cp "$arm_file" "$out_file"
  fi
done < <(find "$arm64_install" -type f)

# ── Package ───────────────────────────────────────────────────────────────────

package_name="ffmpeg-macos-universal-${RELEASE_TAG#ffmpeg-*-*-}"
case "$PACKAGE_FORMAT" in
  tar.gz)
    tar -C "$universal_install" -czf "${package_root}/${package_name}.tar.gz" .
    ;;
  zip)
    (cd "$universal_install" && zip -qry "${package_root}/${package_name}.zip" .)
    ;;
  *)
    fail "Unsupported package format: $PACKAGE_FORMAT"
    ;;
esac

printf 'Universal package created in %s\n' "$package_root"
