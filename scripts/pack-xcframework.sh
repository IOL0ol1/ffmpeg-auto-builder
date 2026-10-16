#!/usr/bin/env bash
# Combine the archives of Apple targets into one XCFramework per library (macOS only).
#
# Usage: pack-xcframework.sh <archives-dir> <output-dir>
# Environment: RELEASE_TAG, CONFIGURE_OPTIONS, PACKAGE_OWNER
#
# Every ffmpeg-<platform>-<arch>-*.zip archive is one target. Targets of the same platform
# and variant (device / simulator) are merged with lipo into one slice, as an XCFramework
# holds one slice per platform variant. Static libraries become library slices with their
# headers (libavcodec/...), shared libraries become .framework bundles (libavcodec.framework,
# install name @rpath/libavcodec.framework/libavcodec), third-party libraries included.
# The result is ffmpeg-apple-xcframework-<license>-<build id>.zip with *.xcframework inside.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

[[ $# -eq 2 ]] || fail "usage: pack-xcframework.sh <archives-dir> <output-dir>"
require_env RELEASE_TAG
archives_dir="$(cd "$1" && pwd)"
mkdir -p "$2"
output_dir="$(cd "$2" && pwd)"
work="${RUNNER_TEMP:-/tmp}/pack-xcframework"
rm -rf "$work"
mkdir -p "$work/slices" "$work/groups" "$work/out"
shopt -s nullglob

owner="$(printf '%s' "${PACKAGE_OWNER:-ffmpeg-auto-builder}" | tr -cd 'A-Za-z0-9-' | tr '[:upper:]' '[:lower:]')"
ffmpeg_libs=(libavutil libswresample libswscale libpostproc libavcodec libavformat libavfilter libavdevice)

# ── Unpack and group the targets ─────────────────────────────────────────────

groups=()
for archive in "$archives_dir"/ffmpeg-*.zip; do
  name="$(basename "$archive")"
  platform="$(cut -d- -f2 <<<"$name")"
  arch="$(cut -d- -f3 <<<"$name")"
  variant="$platform"
  [[ "$arch" != sim_* ]] || variant="$platform-simulator"
  mkdir -p "$work/slices/$variant/$arch"
  unzip -q "$archive" -d "$work/slices/$variant/$arch"
  # ${groups[*]-}: macOS bash 3.2 treats an empty array as unset under set -u.
  [[ " ${groups[*]-} " == *" $variant "* ]] || groups+=("$variant")
done
[[ "${#groups[@]}" -gt 0 ]] || fail "no Apple archives found in $archives_dir"

# One tree per group: the first target, with every Mach-O file lipo'd across the targets.
for group in "${groups[@]}"; do
  slices=("$work/slices/$group"/*)
  tree="$work/groups/$group"
  cp -RP "${slices[0]}" "$tree"
  [[ "${#slices[@]}" -gt 1 ]] || continue
  while IFS= read -r file; do
    rel="${file#"${slices[0]}/"}"
    lipo -info "$file" >/dev/null 2>&1 || continue
    inputs=()
    for slice in "${slices[@]}"; do
      [[ -f "$slice/$rel" ]] && inputs+=("$slice/$rel")
    done
    lipo -create "${inputs[@]}" -output "$tree/$rel"
  done < <(find "${slices[0]}" -type f)
done

# ── Frameworks for shared libraries ──────────────────────────────────────────

is_ffmpeg_lib() {
  [[ " ${ffmpeg_libs[*]} " == *" $1 "* ]]
}

# Info.plist keys that differ per platform: supported platform and minimum OS.
platform_keys() {
  case "$1" in
    ios)                  echo "iPhoneOS MinimumOSVersion 13.0" ;;
    ios-simulator)        echo "iPhoneSimulator MinimumOSVersion 13.0" ;;
    tvos)                 echo "AppleTVOS MinimumOSVersion 13.0" ;;
    tvos-simulator)       echo "AppleTVSimulator MinimumOSVersion 13.0" ;;
    visionos)             echo "XROS MinimumOSVersion 1.0" ;;
    visionos-simulator)   echo "XRSimulator MinimumOSVersion 1.0" ;;
    macos | maccatalyst)  echo "MacOSX LSMinimumSystemVersion 11.0" ;;
  esac
}

# Path of the binary inside <base>.framework: macOS bundles are versioned.
binary_rel() {
  if [[ "$1" == macos || "$1" == maccatalyst ]]; then echo "Versions/A/$2"; else echo "$2"; fi
}

# make_framework <group> <dylib>: wraps a dylib of the group's lib/ as <base>.framework.
make_framework() {
  local group="$1" dylib="$2" tree="$work/groups/$1"
  local base
  base="$(basename "$dylib")"
  base="${base%%.*}"
  local fw="$tree/frameworks/$base.framework" plist supported min_key min_version
  read -r supported min_key min_version <<<"$(platform_keys "$group")"
  rm -rf "$fw"
  # macOS bundles keep their contents in Versions/A (symlinked at the top, below).
  local contents="$fw" resources="$fw"
  if [[ "$group" == macos || "$group" == maccatalyst ]]; then
    contents="$fw/Versions/A"
    resources="$contents/Resources"
  fi
  mkdir -p "$resources"
  cp "$dylib" "$contents/$base"
  plist="$resources/Info.plist"
  if is_ffmpeg_lib "$base" && [[ -d "$tree/include/$base" ]]; then
    mkdir -p "$contents/Headers"
    cp -R "$tree/include/$base/." "$contents/Headers/"
  fi
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$base</string>
  <key>CFBundleIdentifier</key><string>io.github.$owner.ffmpeg.${base//_/-}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$base</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$supported</string></array>
  <key>$min_key</key><string>$min_version</string>
</dict>
</plist>
EOF
  if [[ "$contents" != "$fw" ]]; then
    ln -s A "$fw/Versions/Current"
    local entry
    for entry in "$base" Resources Headers; do
      [[ ! -e "$contents/$entry" ]] || ln -s "Versions/Current/$entry" "$fw/$entry"
    done
  fi
}

version="$(sed -n 's/^ffmpeg_version: *\([0-9][0-9.]*\).*/\1/p' "$work/groups/${groups[0]}/BUILDINFO.txt" 2>/dev/null | head -n 1)"
version="${version:-1.0}"

# Rewrite every @rpath/libfoo.N.dylib reference (install names set by build-ffmpeg.sh) to
# the framework binary of the same library, then re-sign.
link_frameworks() {
  local group="$1" tree="$work/groups/$1" binary dep base
  for binary in "$tree"/frameworks/*.framework/Versions/A/* "$tree"/frameworks/*.framework/*; do
    [[ -f "$binary" && ! -L "$binary" ]] && lipo -info "$binary" >/dev/null 2>&1 || continue
    base="$(basename "$binary")"
    install_name_tool -id "@rpath/$base.framework/$(binary_rel "$group" "$base")" "$binary"
    while IFS= read -r dep; do
      local dep_base="${dep#@rpath/}"
      dep_base="${dep_base%%.*}"
      [[ -d "$tree/frameworks/$dep_base.framework" ]] || continue
      install_name_tool -change "$dep" "@rpath/$dep_base.framework/$(binary_rel "$group" "$dep_base")" "$binary"
    done < <(otool -L "$binary" | awk 'NR > 1 && $1 ~ /^@rpath\/lib[^\/]*\.dylib$/ { print $1 }')
    codesign --force --sign - "$binary" >/dev/null 2>&1 || true
  done
}

for group in "${groups[@]}"; do
  for dylib in "$work/groups/$group"/lib/lib*.dylib; do
    [[ -f "$dylib" && ! -L "$dylib" ]] || continue
    make_framework "$group" "$dylib"
  done
  link_frameworks "$group"
done

# ── XCFrameworks ─────────────────────────────────────────────────────────────

first="$work/groups/${groups[0]}"
names=()
for group in "${groups[@]}"; do
  for file in "$work/groups/$group"/lib/lib*.a "$work/groups/$group"/frameworks/*.framework; do
    base="$(basename "$file")"
    names+=("${base%%.*}")
  done
done
[[ "${#names[@]}" -gt 0 ]] || fail "the archives contain no libraries"

# xcodebuild -create-xcframework <slices> <output>
create_xcframework() {
  local output="${!#}"
  xcodebuild -create-xcframework "${@:1:$#-1}" -output "$output" >/dev/null
}

for base in $(printf '%s\n' "${names[@]}" | sort -u); do
  frameworks=()
  libraries=()
  for group in "${groups[@]}"; do
    tree="$work/groups/$group"
    if [[ -d "$tree/frameworks/$base.framework" ]]; then
      frameworks+=(-framework "$tree/frameworks/$base.framework")
    elif [[ -f "$tree/lib/$base.a" ]]; then
      libraries+=(-library "$tree/lib/$base.a")
      if is_ffmpeg_lib "$base" && [[ -d "$tree/include/$base" ]]; then
        # Headers keep their directory, so #include <libavcodec/avcodec.h> works.
        mkdir -p "$tree/headers/$base"
        cp -R "$tree/include/$base" "$tree/headers/$base/"
        libraries+=(-headers "$tree/headers/$base")
      fi
    fi
  done
  # An XCFramework holds one kind; a library that is a framework on some targets and static
  # on others (shared third-party libraries kept static there) gets a second, -static one.
  if [[ "${#frameworks[@]}" -gt 0 ]]; then
    create_xcframework "${frameworks[@]}" "$work/out/$base.xcframework"
    [[ "${#libraries[@]}" -eq 0 ]] || create_xcframework "${libraries[@]}" "$work/out/$base-static.xcframework"
  else
    create_xcframework "${libraries[@]}" "$work/out/$base.xcframework"
  fi
done
cp "$first/BUILDINFO.txt" "$work/out/BUILDINFO.txt" 2>/dev/null || true

# ffmpeg-apple-xcframework-<license>-<build id>.zip, like the other packages.
sanitize_configure_options "${CONFIGURE_OPTIONS:-}"
package_name="ffmpeg-apple-xcframework-$(license_id "${SANITIZED_CONFIGURE_ARGS[@]}")-${RELEASE_TAG#ffmpeg-*-*-}"
(cd "$work/out" && zip -qry "$output_dir/$package_name.zip" .)
printf 'Packed %s: %s for %s\n' "$package_name.zip" "$(ls "$work/out" | tr '\n' ' ')" "${groups[*]}"
