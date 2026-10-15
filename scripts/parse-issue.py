"""Parse a build request created from one of the .github/ISSUE_TEMPLATE/build*.yml forms.

Reads the issue body from $ISSUE_BODY.
  parse-issue.py          print one "key<TAB>value" line per field (whitespace collapsed)
  parse-issue.py --lang   print only the detected language: zh-CN / en / ja
The language is the one whose form labels match the body best; it decides the language
of the workflow's replies on the issue.
"""
import os
import re
import sys

# Issue form label -> parameter key, per language. Keep in sync with the templates.
LABELS = {
    "zh-CN": {
        "源码仓库": "source_repository",
        "源码分支 / tag / commit": "source_ref",
        "目标平台": "target_platform",
        "目标指令集": "target_arch",
        "打包格式": "package_format",
        "configure 参数": "configure_options",
    },
    "en": {
        "Source repository": "source_repository",
        "Branch / tag / commit": "source_ref",
        "Target platform": "target_platform",
        "Target architecture": "target_arch",
        "Package format": "package_format",
        "configure flags": "configure_options",
    },
    "ja": {
        "ソースリポジトリ": "source_repository",
        "ブランチ / タグ / コミット": "source_ref",
        "ターゲットプラットフォーム": "target_platform",
        "ターゲットアーキテクチャ": "target_arch",
        "パッケージ形式": "package_format",
        "configure フラグ": "configure_options",
    },
}
REQUIRED = ("source_repository", "target_platform", "target_arch", "package_format", "configure_options")
MISSING_MESSAGE = {
    "zh-CN": "Issue 中缺少必填字段：{}。请使用 Issue 模板或 Pages 页面提交。",
    "en": "The issue is missing required fields: {}. Please submit it from the issue template or the Pages site.",
    "ja": "Issue に必須項目がありません：{}。Issue テンプレートまたは Pages から送信してください。",
}
DEFAULT_LANG = "en"

# Messages contain CJK text; do not depend on the runner locale.
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

body = os.environ.get("ISSUE_BODY", "").replace("\r\n", "\n")
sections = {}
for section in re.split(r"^### ", body, flags=re.MULTILINE)[1:]:
    label, _, value = section.partition("\n")
    value = value.strip()
    sections[label.strip()] = "" if value == "_No response_" else " ".join(value.split())

lang = max(LABELS, key=lambda code: sum(label in sections for label in LABELS[code]))
if not any(label in sections for label in LABELS[lang]):
    lang = DEFAULT_LANG

if "--lang" in sys.argv[1:]:
    print(lang)
    sys.exit(0)

labels = LABELS[lang]
fields = {key: sections.get(label, "") for label, key in labels.items()}
missing = [label for label, key in labels.items() if key in REQUIRED and not fields[key]]
if missing:
    separator = ", " if lang == "en" else "、"
    sys.exit(MISSING_MESSAGE[lang].format(separator.join(missing)))

for key in labels.values():
    print(f"{key}\t{fields[key]}")
