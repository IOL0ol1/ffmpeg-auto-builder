#!/usr/bin/env bash
# Post the workflow's replies on a build-request issue in the issue's language (ISSUE_LANG).
#   issue-comment.sh invalid <error-file>   parameters rejected; closes the issue
#   issue-comment.sh started                build accepted; labels the issue
#   issue-comment.sh result                 build finished; closes the issue on success
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/common.sh"

require_env ISSUE_NUMBER
require_env RUN_URL

lang="${ISSUE_LANG:-zh-CN}"

text() {
  case "$lang/$1" in
    en/invalid)        echo 'Invalid parameters; the build was not started.' ;;
    en/invalid_retry)  echo 'Please fix the parameters and submit a new issue.' ;;
    en/run_log)        echo 'Run log: ' ;;
    en/started)        echo '🚀 Build started. Download links will be posted here when it finishes.' ;;
    en/col_param)      echo 'Parameter' ;;
    en/col_value)      echo 'Value' ;;
    en/source)         echo 'Source' ;;
    en/default_branch) echo '(default branch)' ;;
    en/target)         echo 'Target' ;;
    en/format)         echo 'Package format' ;;
    en/progress)       echo 'Progress: ' ;;
    en/ok)             echo '✅ Build finished.' ;;
    en/partial)        echo '⚠️ Some targets failed; the successful packages were published.' ;;
    en/failed)         echo '❌ Build failed; nothing to publish.' ;;
    en/release)        echo 'Draft release (with `SHA256SUMS.txt`): ' ;;
    en/release_note)   echo 'Drafts are visible only to the owner and collaborators; click Publish on the release page to make it public.' ;;
    en/run_details)    echo 'Run details and artifacts: ' ;;
    en/col_job)        echo 'Job' ;;
    en/col_result)     echo 'Result' ;;

    ja/invalid)        echo 'パラメータが不正なため、ビルドは開始されませんでした。' ;;
    ja/invalid_retry)  echo 'パラメータを修正して、新しい Issue を送信してください。' ;;
    ja/run_log)        echo '実行ログ：' ;;
    ja/started)        echo '🚀 ビルドを開始しました。完了するとここにダウンロードリンクを投稿します。' ;;
    ja/col_param)      echo 'パラメータ' ;;
    ja/col_value)      echo '値' ;;
    ja/source)         echo 'ソース' ;;
    ja/default_branch) echo '（デフォルトブランチ）' ;;
    ja/target)         echo 'ターゲット' ;;
    ja/format)         echo 'パッケージ形式' ;;
    ja/progress)       echo '進捗：' ;;
    ja/ok)             echo '✅ ビルドが完了しました。' ;;
    ja/partial)        echo '⚠️ 一部のターゲットが失敗しました。成功したパッケージは公開済みです。' ;;
    ja/failed)         echo '❌ ビルドに失敗しました。公開できるパッケージはありません。' ;;
    ja/release)        echo 'ドラフトリリース（`SHA256SUMS.txt` 付き）：' ;;
    ja/release_note)   echo 'ドラフトはオーナーとコラボレーターのみ閲覧できます。問題がなければリリースページで Publish をクリックして公開してください。' ;;
    ja/run_details)    echo '実行の詳細と Artifact：' ;;
    ja/col_job)        echo 'ジョブ' ;;
    ja/col_result)     echo '結果' ;;

    */invalid)         echo '参数校验失败，未开始编译。' ;;
    */invalid_retry)   echo '请修正参数后重新提交一个新的 Issue。' ;;
    */run_log)         echo '运行日志：' ;;
    */started)         echo '🚀 已开始编译，完成后会在这里回复下载链接。' ;;
    */col_param)       echo '参数' ;;
    */col_value)       echo '值' ;;
    */source)          echo '源码' ;;
    */default_branch)  echo '（默认分支）' ;;
    */target)          echo '目标' ;;
    */format)          echo '打包格式' ;;
    */progress)        echo '运行进度：' ;;
    */ok)              echo '✅ 编译完成。' ;;
    */partial)         echo '⚠️ 部分目标编译失败，成功的产物已发布。' ;;
    */failed)          echo '❌ 编译失败，没有可发布的产物。' ;;
    */release)         echo 'Draft Release（含 `SHA256SUMS.txt`）：' ;;
    */release_note)    echo '草稿仅仓库所有者和协作者可见，确认无误后可在 Release 页面点击 Publish 公开发布。' ;;
    */run_details)     echo '运行详情与 Artifact：' ;;
    */col_job)         echo '任务' ;;
    */col_result)      echo '结果' ;;
  esac
}

comment_file="${RUNNER_TEMP:-/tmp}/issue-comment.md"

case "${1:-}" in
  invalid)
    {
      echo "❌ $(text invalid)"
      echo
      echo '```text'
      cat "${2:-/dev/null}" 2>/dev/null || true
      echo '```'
      echo
      echo "$(text run_log)$RUN_URL"
      echo
      text invalid_retry
    } >"$comment_file"
    gh issue comment "$ISSUE_NUMBER" --body-file "$comment_file"
    gh issue close "$ISSUE_NUMBER" --reason "not planned"
    ;;

  started)
    gh label create build --color 0969da --description "FFmpeg build request" >/dev/null 2>&1 || true
    gh issue edit "$ISSUE_NUMBER" --add-label build >/dev/null 2>&1 || true
    {
      text started
      echo
      echo "| $(text col_param) | $(text col_value) |"
      echo "|---|---|"
      echo "| $(text source) | $SOURCE_REPOSITORY |"
      echo "| ref | ${SOURCE_REF:-$(text default_branch)} |"
      echo "| $(text target) | \`$TARGET\` |"
      echo "| $(text format) | \`$PACKAGE_FORMAT\` |"
      echo "| Release tag | \`$RELEASE_TAG\` |"
      echo "| configure | \`$CONFIGURE_OPTIONS\` |"
      echo
      echo "$(text progress)$RUN_URL"
    } >"$comment_file"
    gh issue comment "$ISSUE_NUMBER" --body-file "$comment_file"
    ;;

  result)
    jobs_json="$(gh api "repos/$GH_REPO/actions/runs/$GITHUB_RUN_ID/jobs?per_page=100")"
    jobs_filter='.jobs[] | select(.name != "setup" and (.name | startswith("release") | not))'
    job_rows="$(jq -r "$jobs_filter"' | "| \(.name) | \(if .conclusion == "success" then "✅" elif .conclusion == "skipped" then "⏭" else "❌" end) \(.conclusion // .status) |"' <<<"$jobs_json")"
    failed_count="$(jq "[$jobs_filter | select(.conclusion != \"success\" and .conclusion != \"skipped\")] | length" <<<"$jobs_json")"

    {
      if [[ "${PUBLISH_OUTCOME:-}" == "success" && "$failed_count" -eq 0 ]]; then
        text ok
      elif [[ "${PUBLISH_OUTCOME:-}" == "success" ]]; then
        text partial
      else
        text failed
      fi
      echo
      if [[ -n "${RELEASE_URL:-}" ]]; then
        echo "- $(text release)$RELEASE_URL"
        echo "  $(text release_note)"
      fi
      echo "- $(text run_details)$RUN_URL"
      echo
      echo "| $(text col_job) | $(text col_result) |"
      echo "|---|---|"
      echo "$job_rows"
    } >"$comment_file"
    gh issue comment "$ISSUE_NUMBER" --body-file "$comment_file"

    if [[ "${PUBLISH_OUTCOME:-}" == "success" ]]; then
      gh issue close "$ISSUE_NUMBER" --reason completed
    fi
    ;;

  *)
    fail "Usage: issue-comment.sh invalid <error-file> | started | result"
    ;;
esac
