#!/usr/bin/env bash
# Resolve build parameters from an issue form (issues event) or workflow_dispatch inputs,
# validate them, and write them together with the build matrix to $GITHUB_OUTPUT.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

# Errors are posted on the issue, so they follow the language of its form (ISSUE_LANG).
# msg <key> [value] [allowed values]
msg() {
  local key="$1" arg="${2:-}" allowed="${3:-}"
  case "${ISSUE_LANG:-en}/$key" in
    ja/platform)       printf 'ターゲットプラットフォームが不正です：%s（%s のいずれか）' "$arg" "$allowed" ;;
    ja/arch)           printf 'ターゲットアーキテクチャが不正です：%s（%s のいずれか）' "$arg" "$allowed" ;;
    ja/archMulti)      printf '複数のアーキテクチャを指定できるのは NuGet パッケージ形式のみです：%s' "$arg" ;;
    ja/nugetPlatform)  printf '%s は静的ライブラリのみ対応のため NuGet パッケージにできません（NuGet は共有ライブラリが必要です）' "$arg" ;;
    ja/format)         printf 'パッケージ形式が不正です：%s（tar.gz / zip / nuget のいずれか）' "$arg" ;;
    ja/repo)           printf 'GitHub リポジトリのみ対応しています：%s' "$arg" ;;
    ja/ref)            printf 'ブランチ / タグ / コミットが不正です：%s' "$arg" ;;
    ja/token)          printf 'configure フラグに使用できない文字が含まれています：%s' "$arg" ;;
    ja/prefix)         printf -- '--prefix は指定できません（インストール先はビルド処理が管理します）' ;;
    zh-CN/platform)    printf '目标平台无效：%s（可选 %s）' "$arg" "$allowed" ;;
    zh-CN/arch)        printf '目标指令集无效：%s（可选 %s）' "$arg" "$allowed" ;;
    zh-CN/archMulti)   printf '只有 NuGet 打包格式可以选择多个指令集：%s' "$arg" ;;
    zh-CN/nugetPlatform) printf '%s 只支持静态库，不能打包为 NuGet（NuGet 包需要共享库）' "$arg" ;;
    zh-CN/format)      printf '打包格式无效：%s（可选 tar.gz / zip / nuget）' "$arg" ;;
    zh-CN/repo)        printf '源码仓库只支持 GitHub 地址：%s' "$arg" ;;
    zh-CN/ref)         printf '源码分支 / tag / commit 无效：%s' "$arg" ;;
    zh-CN/token)       printf 'configure 参数含有不允许的字符：%s' "$arg" ;;
    zh-CN/prefix)      printf -- '不能指定 --prefix：安装路径由编译流程管理' ;;
    */platform)        printf 'Invalid target platform: %s (one of %s)' "$arg" "$allowed" ;;
    */arch)            printf 'Invalid target architecture: %s (one of %s)' "$arg" "$allowed" ;;
    */archMulti)       printf 'Several architectures can only be selected for the NuGet package format: %s' "$arg" ;;
    */nugetPlatform)   printf '%s only supports static libraries, so it cannot be packaged as NuGet (NuGet needs shared libraries)' "$arg" ;;
    */format)          printf 'Invalid package format: %s (one of tar.gz / zip / nuget)' "$arg" ;;
    */repo)            printf 'Only GitHub repositories are supported: %s' "$arg" ;;
    */ref)             printf 'Invalid branch / tag / commit: %s' "$arg" ;;
    */token)           printf 'configure flags contain characters that are not allowed: %s' "$arg" ;;
    */prefix)          printf -- '--prefix cannot be set: the install path is managed by the build' ;;
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

case "$package_format" in
  tar.gz | zip | nuget) ;;
  *) fail "$(msg format "$package_format")" ;;
esac

# Platform and architectures come from docs/targets.json; NuGet takes a comma-separated list
# of architectures, the other formats exactly one.
target_arch="$(printf '%s' "$target_arch" | tr -d ' ')"
if ! resolved="$(python3 -I "$script_dir/targets.py" resolve "$target_platform" "$target_arch" "$package_format")"; then
  IFS=$'\t' read -r _ code value allowed <<<"$resolved"
  fail "$(msg "$code" "$value" "$allowed")"
fi
while IFS='=' read -r key value; do
  printf -v "resolved_$key" '%s' "${value%$'\r'}"
done <<<"$resolved"

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

# ffmpeg-<platform>-<archs joined by ".">-<build id>
release_tag="ffmpeg-${target_platform}-${resolved_archs}-$(date -u +%Y%m%dt%H%M%S)-${tag_suffix}"
validate_release_tag "$release_tag"

{
  echo "source_repository=https://github.com/${source_slug}"
  echo "source_slug=${source_slug}"
  echo "source_ref=${source_ref}"
  echo "target_platform=${target_platform}"
  echo "target_arch=${resolved_archs//./,}"
  echo "package_format=${package_format}"
  echo "archive_format=${archive_format}"
  echo "configure_options=${configure_options}"
  echo "release_tag=${release_tag}"
  echo "matrix=${resolved_matrix}"
  echo "merges=${resolved_merges}"
  echo "needs_merge=${resolved_needs_merge}"
} >>"$GITHUB_OUTPUT"

printf 'Resolved %s/%s from %s → %s\n' "$target_platform" "${resolved_archs//./,}" "$source_slug" "$release_tag"
