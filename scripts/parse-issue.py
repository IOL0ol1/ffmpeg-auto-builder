"""Parse a build request created from .github/ISSUE_TEMPLATE/build.yml.

Reads the issue body from $ISSUE_BODY and prints one "key<TAB>value" line per field.
Whitespace inside values (including newlines) is collapsed to single spaces.
"""
import os
import re
import sys

# Issue form label -> parameter key. Keep in sync with .github/ISSUE_TEMPLATE/build.yml.
LABELS = {
    "源码仓库": "source_repository",
    "源码分支 / tag / commit": "source_ref",
    "目标平台": "target_platform",
    "目标指令集": "target_arch",
    "打包格式": "package_format",
    "configure 参数": "configure_options",
}
REQUIRED = ("source_repository", "target_platform", "target_arch", "package_format", "configure_options")

body = os.environ.get("ISSUE_BODY", "").replace("\r\n", "\n")
fields = {}
for section in re.split(r"^### ", body, flags=re.MULTILINE)[1:]:
    label, _, value = section.partition("\n")
    key = LABELS.get(label.strip())
    if key is None:
        continue
    value = value.strip()
    if value == "_No response_":
        value = ""
    fields[key] = " ".join(value.split())

missing = [label for label, key in LABELS.items() if key in REQUIRED and not fields.get(key)]
if missing:
    sys.exit("Issue 中缺少必填字段：" + "、".join(missing) + "。请使用 Issue 模板或 Pages 页面提交。")

for key in LABELS.values():
    print(f"{key}\t{fields.get(key, '')}")
