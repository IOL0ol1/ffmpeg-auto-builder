#!/usr/bin/env bash
# Merge the single-architecture packages of an Apple target into one fat (universal) package
# with lipo, e.g. macOS x86_64 + arm64 → universal (see "merge" in docs/targets.json).
# Environment: TARGET_PLATFORM, TARGET_ARCH (the merged arch), SLICES (space separated),
# PACKAGE_FORMAT, RELEASE_TAG, CONFIGURE_OPTIONS.
# Input: artifacts/<slice>/ holds the package (tar.gz or zip) of each slice.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"

require_env TARGET_PLATFORM
require_env TARGET_ARCH
require_env SLICES
require_env PACKAGE_FORMAT
require_env RELEASE_TAG
validate_release_tag "$RELEASE_TAG"

work="${RUNNER_TEMP:-/tmp}/merge-slices"
merged="$work/merged"
package_root="$repo_root/dist/packages"
rm -rf "$work" "$repo_root/dist"
mkdir -p "$merged" "$package_root"

extract_package() {
  local pkg_dir="$1" dest="$2" pkg
  pkg="$(find "$pkg_dir" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.zip' \) | head -n 1)"
  [[ -n "$pkg" ]] || fail "No package found in $pkg_dir"
  mkdir -p "$dest"
  case "$pkg" in
    *.tar.gz) tar -xzf "$pkg" -C "$dest" ;;
    *.zip)    unzip -q "$pkg" -d "$dest" ;;  # unzip keeps exec bits and symlinks
  esac
}

read -r -a slices <<<"$SLICES"
for slice in "${slices[@]}"; do
  extract_package "$repo_root/artifacts/$slice" "$work/$slice"
done

# Start from a complete copy of the first slice (symlinks, headers, pkg-config files, ...),
# then lipo every Mach-O file (executables, dylibs, static archives) with the other slices.
first="$work/${slices[0]}"
cp -RP "$first/." "$merged/"
while IFS= read -r file; do
  rel="${file#"$first/"}"
  lipo -info "$file" >/dev/null 2>&1 || continue
  inputs=("$file")
  for slice in "${slices[@]:1}"; do
    [[ -f "$work/$slice/$rel" ]] && inputs+=("$work/$slice/$rel")
  done
  [[ "${#inputs[@]}" -gt 1 ]] || continue
  lipo -create "${inputs[@]}" -output "$merged/$rel" || fail "lipo failed for $rel"
done < <(find "$first" -type f)

# BUILDINFO.txt describes the first slice; record the merged architecture instead.
sed -i.bak "s/^arch: .*/arch: ${TARGET_ARCH} (${SLICES})/" "$merged/BUILDINFO.txt" && rm -f "$merged/BUILDINFO.txt.bak"

sanitize_configure_options "${CONFIGURE_OPTIONS:-}"
package_name="ffmpeg-${TARGET_PLATFORM}-${TARGET_ARCH}-$(license_id "${SANITIZED_CONFIGURE_ARGS[@]}")-${RELEASE_TAG#ffmpeg-*-*-}"
case "$PACKAGE_FORMAT" in
  tar.gz) tar -C "$merged" -czf "$package_root/${package_name}.tar.gz" . ;;
  zip)    (cd "$merged" && zip -qry "$package_root/${package_name}.zip" .) ;;
  *)      fail "Unsupported package format: $PACKAGE_FORMAT" ;;
esac

printf 'Merged %s into %s\n' "$SLICES" "$package_root/$package_name"
