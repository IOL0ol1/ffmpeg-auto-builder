#!/usr/bin/env bash
# Resolve build parameters from an issue form (issues event) or workflow_dispatch inputs,
# validate them, and write them together with the build matrix to $GITHUB_OUTPUT.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

require_env EVENT_NAME
require_env GITHUB_OUTPUT

if [[ "$EVENT_NAME" == "issues" ]]; then
  require_env ISSUE_NUMBER
  parsed="$(python3 -I "$script_dir/parse-issue.py")"
  while IFS=$'\t' read -r key value; do
    printf -v "$key" '%s' "${value%$'\r'}"
  done <<<"$parsed"
  tag_suffix="i${ISSUE_NUMBER}"
else
  source_repository="${INPUT_SOURCE_REPOSITORY:-}"
  source_ref="${INPUT_SOURCE_REF:-}"
  target_platform="${INPUT_TARGET_PLATFORM:-}"
  target_arch="${INPUT_TARGET_ARCH:-}"
  package_format="${INPUT_PACKAGE_FORMAT:-}"
  configure_options="${INPUT_CONFIGURE_OPTIONS:-}"
  tag_suffix="r${GITHUB_RUN_ID:-0}"
fi

# ── Validate ─────────────────────────────────────────────────────────────────

case "$target_platform" in
  linux | macos | windows | all) ;;
  *) fail "目标平台无效：${target_platform}（可选 linux / macos / windows / all）" ;;
esac
case "$target_arch" in
  x86_64 | x86 | arm64 | armv7 | universal) ;;
  *) fail "目标指令集无效：${target_arch}（可选 x86_64 / x86 / arm64 / armv7 / universal）" ;;
esac
case "$package_format" in
  tar.gz | zip) ;;
  *) fail "打包格式无效：${package_format}（可选 tar.gz / zip）" ;;
esac

source_slug="$(parse_repository_slug "$source_repository")"
if [[ -n "$source_ref" && ! "$source_ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
  fail "源码分支 / tag / commit 无效：${source_ref}"
fi

sanitize_configure_options "$configure_options"
configure_options="${SANITIZED_CONFIGURE_ARGS[*]}"

release_tag="ffmpeg-${target_platform}-${target_arch}-$(date -u +%Y%m%dt%H%M%S)-${tag_suffix}"
validate_release_tag "$release_tag"

# ── Build matrix ─────────────────────────────────────────────────────────────

mingw64_pkgs="make diffutils zip mingw-w64-x86_64-toolchain mingw-w64-x86_64-pkgconf mingw-w64-x86_64-nasm mingw-w64-x86_64-ccache"
mingw32_pkgs="make diffutils zip mingw-w64-i686-toolchain mingw-w64-i686-pkgconf mingw-w64-i686-nasm mingw-w64-i686-ccache"
clangarm64_pkgs="make diffutils zip mingw-w64-clang-aarch64-toolchain mingw-w64-clang-aarch64-pkgconf mingw-w64-clang-aarch64-ccache"

entries=()
needs_lipo="false"

# add <platform> <runner> <arch> [cross_prefix] [msystem] [msys2_packages] [universal_slice]
# All values are constants from this script, so plain string formatting yields valid JSON.
add() {
  entries+=("$(printf '{"platform":"%s","os":"%s","arch":"%s","cross_prefix":"%s","msystem":"%s","msys2_packages":"%s","universal_slice":"%s"}' \
    "$1" "$2" "$3" "${4:-}" "${5:-}" "${6:-}" "${7:-}")")
}

if [[ "$target_platform" == "all" ]]; then
  platforms=(linux macos windows)
else
  platforms=("$target_platform")
fi

for p in "${platforms[@]}"; do
  case "$p/$target_arch" in
    linux/x86_64 | linux/universal) add linux ubuntu-latest x86_64 ;;
    linux/x86)       add linux ubuntu-latest x86 i686-linux-gnu- ;;
    linux/arm64)     add linux ubuntu-24.04-arm arm64 ;;
    linux/armv7)     add linux ubuntu-latest armv7 arm-linux-gnueabihf- ;;
    macos/x86_64)    add macos macos-15-intel x86_64 ;;
    macos/arm64)     add macos macos-15 arm64 ;;
    macos/universal)
      add macos macos-15-intel x86_64 "" "" "" true
      add macos macos-15 arm64 "" "" "" true
      needs_lipo="true"
      ;;
    windows/x86_64 | windows/universal) add windows windows-latest x86_64 "" MINGW64 "$mingw64_pkgs" ;;
    windows/x86)     add windows windows-latest x86 "" MINGW32 "$mingw32_pkgs" ;;
    windows/arm64)   add windows windows-11-arm arm64 "" CLANGARM64 "$clangarm64_pkgs" ;;
    *) echo "::warning::Skipping unsupported combination $p/$target_arch" ;;
  esac
done

[[ "${#entries[@]}" -gt 0 ]] || fail "没有可构建的目标：${target_platform}/${target_arch}"

matrix="$(IFS=,; printf '{"include":[%s]}' "${entries[*]}")"

{
  echo "source_repository=https://github.com/${source_slug}"
  echo "source_slug=${source_slug}"
  echo "source_ref=${source_ref}"
  echo "target_platform=${target_platform}"
  echo "target_arch=${target_arch}"
  echo "package_format=${package_format}"
  echo "configure_options=${configure_options}"
  echo "release_tag=${release_tag}"
  echo "matrix=${matrix}"
  echo "needs_lipo=${needs_lipo}"
} >>"$GITHUB_OUTPUT"

printf 'Resolved %s/%s from %s → %s\n' "$target_platform" "$target_arch" "$source_slug" "$release_tag"
