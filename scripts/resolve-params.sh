#!/usr/bin/env bash
# Resolve build parameters from an issue form (issues event) or workflow_dispatch inputs,
# validate them, and write them together with the build matrix to $GITHUB_OUTPUT.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

# Errors are posted on the issue, so they follow the language of its form (ISSUE_LANG).
msg() {
  local key="$1" arg="${2:-}"
  case "${ISSUE_LANG:-en}/$key" in
    ja/platform)    printf 'ターゲットプラットフォームが不正です：%s（linux / macos / windows / all のいずれか）' "$arg" ;;
    ja/arch)        printf 'ターゲットアーキテクチャが不正です：%s（x86_64 / x86 / arm64 / armv7 / universal のいずれか）' "$arg" ;;
    ja/format)      printf 'パッケージ形式が不正です：%s（tar.gz / zip のいずれか）' "$arg" ;;
    ja/repo)        printf 'GitHub リポジトリのみ対応しています：%s' "$arg" ;;
    ja/ref)         printf 'ブランチ / タグ / コミットが不正です：%s' "$arg" ;;
    ja/token)       printf 'configure フラグに使用できない文字が含まれています：%s' "$arg" ;;
    ja/prefix)      printf -- '--prefix は指定できません（インストール先はビルド処理が管理します）' ;;
    ja/target)      printf 'ビルドできるターゲットがありません：%s' "$arg" ;;
    zh-CN/platform) printf '目标平台无效：%s（可选 linux / macos / windows / all）' "$arg" ;;
    zh-CN/arch)     printf '目标指令集无效：%s（可选 x86_64 / x86 / arm64 / armv7 / universal）' "$arg" ;;
    zh-CN/format)   printf '打包格式无效：%s（可选 tar.gz / zip）' "$arg" ;;
    zh-CN/repo)     printf '源码仓库只支持 GitHub 地址：%s' "$arg" ;;
    zh-CN/ref)      printf '源码分支 / tag / commit 无效：%s' "$arg" ;;
    zh-CN/token)    printf 'configure 参数含有不允许的字符：%s' "$arg" ;;
    zh-CN/prefix)   printf -- '不能指定 --prefix：安装路径由编译流程管理' ;;
    zh-CN/target)   printf '没有可构建的目标：%s' "$arg" ;;
    */platform)     printf 'Invalid target platform: %s (one of linux / macos / windows / all)' "$arg" ;;
    */arch)         printf 'Invalid target architecture: %s (one of x86_64 / x86 / arm64 / armv7 / universal)' "$arg" ;;
    */format)       printf 'Invalid package format: %s (one of tar.gz / zip)' "$arg" ;;
    */repo)         printf 'Only GitHub repositories are supported: %s' "$arg" ;;
    */ref)          printf 'Invalid branch / tag / commit: %s' "$arg" ;;
    */token)        printf 'configure flags contain characters that are not allowed: %s' "$arg" ;;
    */prefix)       printf -- '--prefix cannot be set: the install path is managed by the build' ;;
    */target)       printf 'No buildable target for %s' "$arg" ;;
  esac
}

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
  *) fail "$(msg platform "$target_platform")" ;;
esac
case "$target_arch" in
  x86_64 | x86 | arm64 | armv7 | universal) ;;
  *) fail "$(msg arch "$target_arch")" ;;
esac
case "$package_format" in
  tar.gz | zip) ;;
  *) fail "$(msg format "$package_format")" ;;
esac

source_slug="$(parse_repository_slug "$source_repository" 2>/dev/null)" || fail "$(msg repo "$source_repository")"
if [[ -n "$source_ref" && ! "$source_ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
  fail "$(msg ref "$source_ref")"
fi

# Check tokens here for a localized message; sanitize_configure_options repeats the checks.
read -r -a raw_tokens <<<"$(printf '%s' "$configure_options" | tr '\r\n\t' '   ')"
for token in "${raw_tokens[@]}"; do
  [[ "$token" =~ $SAFE_TOKEN_PATTERN ]] || fail "$(msg token "$token")"
  [[ "$token" != --prefix=* ]] || fail "$(msg prefix)"
done
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

[[ "${#entries[@]}" -gt 0 ]] || fail "$(msg target "${target_platform}/${target_arch}")"

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
