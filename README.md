# FFmpeg Auto Builder

基于 **GitHub Pages + GitHub Actions** 的 FFmpeg 在线自动编译模板仓库。任何人 Fork 后，只需开启 `docs/` 目录 Pages，即可获得一套纯 GitHub 生态、无需第三方后端的可视化编译工具。

## 功能概览

- 自动识别当前 GitHub Pages 所属的 Fork 仓库，无需手动填写 owner/repo。
- 静态网页提交 FFmpeg 源码仓库地址、编译参数、目标平台与打包格式。
- 支持使用用户自带 GitHub Classic PAT 拉取公有/私有 FFmpeg Fork。
- Workflow 自动执行依赖安装、参数安全过滤、编译、打包、Artifact 上传与 Draft Release 发布。
- 页面可查询最近任务状态，并展示 Actions 运行链接、Artifact 链接与 Draft Release 链接。
- 代码中不硬编码仓库名、用户名、密钥，Fork 后无需改代码即可使用。

## 目录结构

```text
.
├── .github/workflows/build.yml   # 通用编译流水线
├── docs/                         # GitHub Pages 前端
└── scripts/                      # 跨平台安装/编译脚本
```

## 快速部署

1. Fork 本仓库。
2. 打开 Fork 仓库的 **Settings → Pages**。
3. 在 **Build and deployment** 中选择：
   - **Source**: `Deploy from a branch`
   - **Branch**: 默认分支
   - **Folder**: `/docs`
4. 保存后等待 Pages 发布完成。
5. 打开你的 Pages 链接，即可看到编译表单。

## PAT 申请教程

本项目使用 **GitHub Classic PAT**，推荐最小权限：

- `repo`：允许访问私有源码仓库与 Draft Release。
- `workflow`：允许触发当前 Fork 仓库的工作流。

申请步骤：

1. 打开 GitHub **Settings → Developer settings → Personal access tokens → Tokens (classic)**。
2. 点击 **Generate new token (classic)**。
3. 勾选 `repo` 与 `workflow` 权限。
4. 复制并妥善保存令牌。
5. 在 Pages 页面中粘贴使用。页面不会写入 `localStorage`、`sessionStorage` 或仓库代码。

## 使用私有 FFmpeg 仓库

1. 准备一个你自己可访问的 GitHub FFmpeg 仓库（支持私有仓库）。
2. 在 Pages 表单中填入：
   - 你的 GitHub Classic PAT
   - 私有仓库 HTTPS 地址，例如 `https://github.com/your-name/ffmpeg.git`
   - `configure` 编译参数
   - 目标平台 / 打包格式
3. 提交后前端会校验：
   - PAT 所属用户是否等于当前 Fork 仓库所有者
   - 目标仓库是否由本仓库工作流触发
4. Workflow 会使用临时鉴权 URL 拉取源码，并在克隆后立即把 `origin` 远端还原成无凭证地址，同时清理可能残留的 Git 凭证文件。

## 安全设计

- PAT 只保存在浏览器内存与当前 workflow 输入中，不写入页面持久化存储。
- 页面会在触发前校验 PAT 所属账号必须与当前 Fork 仓库 owner 一致，避免跨账号触发。
- `scripts/common.sh` 会过滤 `configure` 参数中的危险字符，拒绝 `; & | $ > \`` 等注入风险。
- 工作流启动后立即对 PAT 执行 `add-mask`，并在源码克隆完成后移除带凭证的远端地址。
- 仅支持 GitHub 仓库地址，避免 PAT 被发送到非 GitHub 域名。

## 编译流程

1. Pages 前端识别当前仓库并查询默认分支。
2. 使用用户 PAT 调用 GitHub Actions `workflow_dispatch`。
3. Workflow 根据平台选择对应 runner：
   - `ubuntu-latest`
   - `macos-latest`
   - `windows-latest`
4. `scripts/install-deps.sh` 安装依赖。
5. `scripts/build-ffmpeg.sh`：
   - 规范化 GitHub 仓库地址
   - 拼接临时鉴权克隆地址
   - 过滤 `configure` 参数
   - 执行 `./configure && make && make install`
   - 输出 `tar.gz` 或 `zip` 安装包
6. 工作流上传 Artifact，并创建/更新同名 Draft Release。

## 前端使用说明

Pages 页面提供：

- 仓库自动识别
- 编译参数模板
- 构建提交
- 当前任务状态轮询
- 最近 10 条工作流运行记录

默认模板仅覆盖常见选项；如果你需要更复杂的编译参数，请使用空格分隔的安全 token，例如：

```text
--disable-debug --disable-doc --enable-gpl --enable-version3 --enable-shared
```

## 可选优化方案

以下功能未默认启用，但可以在 Fork 中继续扩展：

- 使用 `actions/cache` 缓存依赖或编译中间产物
- 改成 matrix 并行构建多个平台
- 在 Pages 中增加历史任务本地缓存（仍不保存 PAT）
- 嵌入日志查看器，直接展示单次运行日志摘要
- 增加源码分支 / tag / commit 指定编译

## 许可证

本仓库已附带 **MIT License**，支持任意个人或商用 Fork、自定义和再分发。