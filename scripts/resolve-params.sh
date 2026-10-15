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
    ja/platform)    printf 'ターゲットプラットフォームが不正です：%s（linux / macos / windows のいずれか）' "$arg" ;;
    ja/arch)        printf 'ターゲットアーキテクチャが不正です：%s（x86_64 / x86 / arm64 / armv7 / universal / all のいずれか）' "$arg" ;;
    ja/archAll)     printf 'アーキテクチャ all は NuGet パッケージ形式でのみ使用できます' ;;
    ja/format)      printf 'パッケージ形式が不正です：%s（tar.gz / zip / nuget のいずれか）' "$arg" ;;
    ja/repo)        printf 'GitHub リポジトリのみ対応しています：%s' "$arg" ;;
    ja/ref)         printf 'ブランチ / タグ / コミットが不正です：%s' "$arg" ;;
    ja/token)       printf 'configure フラグに使用できない文字が含まれています：%s' "$arg" ;;
    ja/prefix)      printf -- '--prefix は指定できません（インストール先はビルド処理が管理します）' ;;
    ja/target)      printf 'ビルドできるターゲットがありません：%s' "$arg" ;;
    zh-CN/platform) printf '目标平台无效：%s（可选 linux / macos / windows）' "$arg" ;;
    zh-CN/arch)     printf '目标指令集无效：%s（可选 x86_64 / x86 / arm64 / armv7 / universal / all）' "$arg" ;;
    zh-CN/archAll)  printf '指令集 all 仅适用于 NuGet 打包格式' ;;
    zh-CN/format)   printf '打包格式无效：%s（可选 tar.gz / zip / nuget）' "$arg" ;;
    zh-CN/repo)     printf '源码仓库只支持 GitHub 地址：%s' "$arg" ;;
    zh-CN/ref)      printf '源码分支 / tag / commit 无效：%s' "$arg" ;;
    zh-CN/token)    printf 'configure 参数含有不允许的字符：%s' "$arg" ;;
    zh-CN/prefix)   printf -- '不能指定 --prefix：安装路径由编译流程管理' ;;
    zh-CN/target)   printf '没有可构建的目标：%s' "$arg" ;;
    */platform)     printf 'Invalid target platform: %s (one of linux / macos / windows)' "$arg" ;;
    */arch)         printf 'Invalid target architecture: %s (one of x86_64 / x86 / arm64 / armv7 / universal / all)' "$arg" ;;
    */archAll)      printf 'The "all" architecture is only available for the NuGet package format' ;;
    */format)       printf 'Invalid package format: %s (one of tar.gz / zip / nuget)' "$arg" ;;
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
  linux | macos | windows) ;;
  *) fail "$(msg platform "$target_platform")" ;;
esac
case "$target_arch" in
  x86_64 | x86 | arm64 | armv7 | universal | all) ;;
  *) fail "$(msg arch "$target_arch")" ;;
esac
case "$package_format" in
  tar.gz | zip | nuget) ;;
  *) fail "$(msg format "$package_format")" ;;
esac
# "all" puts every architecture of the platform into one NuGet package.
[[ "$target_arch" != "all" || "$package_format" == "nuget" ]] || fail "$(msg archAll)"

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

# NuGet packages carry shared libraries only; appended last so they win over earlier flags.
# The platform builds are archived as zip and combined into one .nupkg by the release job.
archive_format="$package_format"
if [[ "$package_format" == "nuget" ]]; then
  configure_options+=" --enable-shared --disable-static"
  archive_format="zip"
fi

release_tag="ffmpeg-${target_platform}-${target_arch}-$(date -u +%Y%m%dt%H%M%S)-${tag_suffix}"
validate_release_tag "$release_tag"

# ── Build matrix ─────────────────────────────────────────────────────────────

# Every target gets the third-party libraries (deps/*.sh, see scripts/toolchain.sh):
# Linux x86_64 / arm64 build in a manylinux_2_28 container (glibc 2.28), Linux x86 / armv7
# are cross-compiled in an Ubuntu 20.04 container (glibc 2.31), Windows is cross-compiled
# with llvm-mingw on Ubuntu, macOS builds natively.
manylinux_x64="quay.io/pypa/manylinux_2_28_x86_64"
manylinux_arm64="quay.io/pypa/manylinux_2_28_aarch64"
linux32="ubuntu:20.04"

entries=()
needs_lipo="false"

# add <platform> <runner> <arch> [container] [universal_slice]
# All values are constants from this script, so plain string formatting yields valid JSON.
add() {
  entries+=("$(printf '{"platform":"%s","os":"%s","arch":"%s","deps":"true","container":"%s","universal_slice":"%s"}' \
    "$1" "$2" "$3" "${4:-}" "${5:-}")")
}

add_target() {
  case "$1/$2" in
    linux/x86_64)   add linux ubuntu-latest x86_64 "$manylinux_x64" ;;
    linux/arm64)    add linux ubuntu-24.04-arm arm64 "$manylinux_arm64" ;;
    linux/x86)      add linux ubuntu-latest x86 "$linux32" ;;
    linux/armv7)    add linux ubuntu-latest armv7 "$linux32" ;;
    macos/x86_64)   add macos macos-15-intel x86_64 ;;
    macos/arm64)    add macos macos-15 arm64 ;;
    windows/x86_64) add windows ubuntu-latest x86_64 ;;
    windows/x86)    add windows ubuntu-latest x86 ;;
    windows/arm64)  add windows ubuntu-latest arm64 ;;
    *) echo "::warning::Skipping unsupported combination $1/$2" ;;
  esac
}

case "$target_platform/$target_arch" in
  macos/universal)
    add macos macos-15-intel x86_64 "" true
    add macos macos-15 arm64 "" true
    # NuGet uses the two slices as osx-x64 / osx-arm64 instead of a merged binary.
    [[ "$package_format" == "nuget" ]] || needs_lipo="true"
    ;;
  linux/universal | windows/universal) add_target "$target_platform" x86_64 ;;
  linux/all)   for a in x86_64 arm64 x86 armv7; do add_target linux "$a"; done ;;
  macos/all)   for a in x86_64 arm64; do add_target macos "$a"; done ;;
  windows/all) for a in x86_64 x86 arm64; do add_target windows "$a"; done ;;
  *)           add_target "$target_platform" "$target_arch" ;;
esac

[[ "${#entries[@]}" -gt 0 ]] || fail "$(msg target "${target_platform}/${target_arch}")"

matrix="$(IFS=,; printf '{"include":[%s]}' "${entries[*]}")"

{
  echo "source_repository=https://github.com/${source_slug}"
  echo "source_slug=${source_slug}"
  echo "source_ref=${source_ref}"
  echo "target_platform=${target_platform}"
  echo "target_arch=${target_arch}"
  echo "package_format=${package_format}"
  echo "archive_format=${archive_format}"
  echo "configure_options=${configure_options}"
  echo "release_tag=${release_tag}"
  echo "matrix=${matrix}"
  echo "needs_lipo=${needs_lipo}"
} >>"$GITHUB_OUTPUT"

printf 'Resolved %s/%s from %s → %s\n' "$target_platform" "$target_arch" "$source_slug" "$release_tag"
