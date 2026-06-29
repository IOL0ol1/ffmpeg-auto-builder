# FFmpeg Auto Builder

基于 **GitHub Pages + GitHub Actions** 的 FFmpeg 在线自动编译模板仓库。任何人 Fork 后，只需开启 `docs/` 目录 Pages，即可获得一套纯 GitHub 生态、无需第三方后端的可视化编译工具。

## 功能概览

- 自动识别当前 GitHub Pages 所属的 Fork 仓库，无需手动填写 owner/repo。
- 静态网页提交 FFmpeg 源码仓库地址、源码分支/tag/commit、编译参数、目标平台与打包格式。
- 支持使用用户自带 GitHub Classic PAT 拉取公有/私有 FFmpeg Fork。
- Workflow 自动执行依赖缓存与安装、参数安全过滤、编译、打包、Artifact 上传与 Draft Release 发布。
- 支持 Linux / macOS / Windows 三平台并行构建，macOS 可生成包含 x86_64 + arm64 的通用（Universal）Fat Binary。
- Linux 支持 x86、arm64、armv7 交叉编译；Windows 通过 MSYS2 支持 x86_64、x86、arm64、armv7。
- 页面可查询当前任务状态（含内联 Job/Step 日志摘要），并展示 Actions 运行链接、Artifact 链接与 Draft Release 链接。
- 本地历史记录（最多 30 条，不含 PAT）保存在 `localStorage`，支持点击刷新运行状态。
- 代码中不硬编码仓库名、用户名、密钥，Fork 后无需改代码即可使用。

## 目录结构

```text
.
├── .github/workflows/build.yml   # 通用编译流水线（setup → build matrix → lipo）
├── docs/                         # GitHub Pages 前端（index.html / app.js / styles.css）
└── scripts/
    ├── common.sh                 # 公共工具函数（URL 规范化、参数过滤等）
    ├── install-deps.sh           # 跨平台依赖安装（apt / brew / MSYS2 pacman）
    ├── build-ffmpeg.sh           # 克隆源码、编译并打包
    └── lipo-universal.sh         # 将 x86_64 + arm64 包合并为 macOS 通用二进制
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
5. 在 Pages 页面中粘贴使用。PAT 仅保存在浏览器内存中，不写入 `localStorage`、`sessionStorage` 或仓库代码。

## 使用私有 FFmpeg 仓库

1. 准备一个你自己可访问的 GitHub FFmpeg 仓库（支持私有仓库）。
2. 在 Pages 表单中填入：
   - 你的 GitHub Classic PAT
   - 私有仓库地址（HTTPS 或 SSH 均可，例如 `https://github.com/your-name/ffmpeg.git` 或 `git@github.com:your-name/ffmpeg.git`）
   - 源码分支 / tag / commit（可选，留空则使用默认分支 HEAD）
   - `configure` 编译参数
   - 目标平台 / 目标指令集 / 打包格式
3. 提交前前端会校验：
   - PAT 所属用户是否与当前 Fork 仓库所有者一致
4. Workflow 也会再次校验 PAT owner，然后使用临时鉴权 URL 拉取源码，克隆完成后立即把 `origin` 远端还原为无凭证地址，并清理可能残留的 Git 凭证文件。

## 安全设计

- PAT 只保存在浏览器内存与当前 workflow 输入中，不写入页面持久化存储，本地历史记录也不含 PAT。
- 前端与 workflow 均会校验 PAT 所属账号必须与当前 Fork 仓库 owner 一致，避免跨账号触发。
- `scripts/common.sh` 会过滤 `configure` 参数中的危险字符，仅允许 `[-+./:=,@%A-Za-z0-9_]` 安全字符集，拒绝 `; & | $ > \`` 等注入风险。
- 工作流启动后立即对 PAT 执行 `add-mask`，并在源码克隆完成后移除带凭证的远端地址。
- 仅支持 GitHub 仓库地址，避免 PAT 被发送到非 GitHub 域名。

## 编译流程

1. Pages 前端识别当前仓库并查询默认分支。
2. 使用用户 PAT 调用 GitHub Actions `workflow_dispatch`，传入以下参数：
   - `source_repository`：FFmpeg 源码仓库地址
   - `source_ref`：分支 / tag / commit（可选）
   - `github_pat`：GitHub Classic PAT
   - `target_platform`：`linux` / `macos` / `windows` / `all`
   - `target_arch`：`x86_64` / `x86` / `arm64` / `armv7` / `universal`
   - `package_format`：`tar.gz` / `zip`
   - `configure_options`：FFmpeg configure 参数
   - `release_tag`：Draft Release 标签名
3. **setup** 任务根据 `target_platform` × `target_arch` 生成 matrix，并确定是否需要 lipo 合并。
4. **build** 矩阵并行执行，每个 job：
   - 使用 `actions/cache` 缓存 apt / Homebrew / MSYS2 包。
   - `scripts/install-deps.sh` 安装平台对应工具链（含交叉编译器）。
   - 校验 PAT owner 后，`scripts/build-ffmpeg.sh` 克隆源码、执行 `./configure && make && make install`、打包输出。
   - 上传 Artifact 并创建/更新同名 Draft Release。
5. **lipo**（仅 `macos/universal`）：下载 x86_64 与 arm64 产物，通过 `scripts/lipo-universal.sh` 合并为通用二进制后再次上传 Artifact 并发布 Draft Release。

### 平台与指令集对照表

| 平台    | 指令集       | Runner              | 说明                          |
|---------|-------------|---------------------|-------------------------------|
| linux   | x86_64      | ubuntu-latest       | 原生编译                      |
| linux   | x86         | ubuntu-latest       | `i686-linux-gnu` 交叉编译     |
| linux   | arm64       | ubuntu-24.04-arm    | 原生 ARM runner               |
| linux   | armv7       | ubuntu-latest       | `arm-linux-gnueabihf` 交叉编译|
| macos   | x86_64      | macos-13            | 原生编译                      |
| macos   | arm64       | macos-latest        | 原生编译                      |
| macos   | universal   | macos-13 + macos-latest | 先分别编译，再 lipo 合并  |
| windows | x86_64      | windows-latest      | MSYS2 MINGW64                 |
| windows | x86         | windows-latest      | MSYS2 MINGW32                 |
| windows | arm64       | windows-latest      | MSYS2 CLANGARM64              |
| windows | armv7       | windows-latest      | MSYS2 CLANGARM32              |

> 选择 `target_platform = all` 时，Linux / macOS / Windows 三平台同时并行构建。
> macOS / Windows 选择 `universal` 时，分别退化为 x86_64。

## 前端使用说明

Pages 页面提供：

- 仓库与默认分支自动识别
- 常用编译参数模板（精简构建、共享库、静态库）
- 源码分支 / tag / commit 指定（可选）
- 构建提交与 PAT owner 校验
- 当前任务状态轮询（含内联 Job/Step 日志摘要，可展开/收起）
- 最近 workflow_dispatch 任务列表
- 本地历史记录（最多 30 条，保存到 `localStorage`，不含 PAT）

默认模板仅覆盖常见选项；如果你需要更复杂的编译参数，请使用空格分隔的安全 token，例如：

```text
--disable-debug --disable-doc --enable-gpl --enable-version3 --enable-shared
```

## 可扩展方向

以下功能可在 Fork 中按需扩展：

- 增加 `ccache` 或编译中间产物缓存，进一步加速重复编译
- 支持在 Pages 中配置并保存多套 configure 预设
- 增加 webhook 或邮件通知，构建完成后自动提醒

## 许可证

本仓库已附带 **MIT License**，支持任意个人或商用 Fork、自定义和再分发。