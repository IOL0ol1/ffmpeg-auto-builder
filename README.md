# FFmpeg Auto Builder

基于 **GitHub Pages + GitHub Actions** 的 FFmpeg 在线自动编译模板仓库。任何人 Fork 后，只需开启 `docs/` 目录 Pages，即可获得一套纯 GitHub 生态、无需第三方后端的可视化编译工具。

## 功能概览

- 自动识别当前 GitHub Pages 所属的 Fork 仓库，无需手动填写 owner/repo。
- 静态网页提交 FFmpeg 源码仓库地址、源码分支/tag/commit、编译参数、目标平台与打包格式。
- 支持公有 FFmpeg 仓库；配置 `SOURCE_PAT` Secret 后支持私有 FFmpeg Fork。
- Workflow 自动执行参数安全过滤、ccache 增量编译、编译、冒烟测试、打包、Artifact 上传，并统一发布一个 Draft Release（附 `SHA256SUMS.txt`）。
- 支持 Linux / macOS / Windows 三平台并行构建，macOS 可生成 x86_64 + arm64 通用（Universal）二进制。
- Linux 支持 x86、arm64、armv7；Windows 通过 MSYS2 支持 x86_64、x86、arm64。
- 产物可直接解压使用：共享库构建自动修正 rpath / install name，`.pc` 文件改为相对路径，Windows 包自动附带 MinGW 运行时 DLL，包内附 `BUILDINFO.txt` 记录源码 commit 与编译参数。
- 页面可查询当前任务状态（含内联 Job/Step 日志摘要），并展示 Actions 运行链接、Artifact 链接与 Draft Release 链接。
- 本地历史记录（最多 30 条，不含 PAT）保存在 `localStorage`，支持点击刷新运行状态。
- 代码中不硬编码仓库名、用户名、密钥，Fork 后无需改代码即可使用。

## 目录结构

```text
.
├── .github/workflows/build.yml   # 编译流水线（setup → build matrix → lipo → release）
├── docs/                         # GitHub Pages 前端（index.html / app.js / styles.css）
└── scripts/
    ├── common.sh                 # 公共工具函数（仓库地址解析、参数过滤等）
    ├── install-deps.sh           # Linux / macOS 依赖安装（apt / brew）
    ├── build-ffmpeg.sh           # 编译、修正产物路径、冒烟测试并打包
    └── lipo-universal.sh         # 将 x86_64 + arm64 包合并为 macOS 通用二进制
```

## 使用教程

### 第 1 步：Fork 并开启 Pages

1. 点击右上角 **Fork**，把本仓库复制到你自己的账号（或你有写权限的组织）下。
2. 打开 Fork 仓库的 **Actions** 页面，点击 **I understand my workflows, go ahead and enable them**（Fork 仓库默认禁用 Actions）。
3. 打开 **Settings → Pages**，在 **Build and deployment** 中选择：
   - **Source**：`Deploy from a branch`
   - **Branch**：默认分支，**Folder**：`/docs`
4. 保存后等待 1～2 分钟，页面顶部会显示 Pages 地址，形如 `https://<你的用户名>.github.io/<仓库名>/`。

### 第 2 步：创建用于网页触发的 PAT

网页需要一个 PAT 来调用 GitHub API 触发工作流。**这个 PAT 只在浏览器内存中使用，不会传给工作流，也不会出现在日志里。**

推荐使用 **Fine-grained PAT**（权限最小）：

1. 打开 GitHub **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**。
2. **Repository access** 选择 **Only select repositories**，只勾选你的 Fork 仓库。
3. **Repository permissions** 中设置：
   - `Actions`：**Read and write**（触发工作流、查看运行状态）
   - `Contents`：**Read and write**（查看 Draft Release；草稿仅对有写权限的用户可见）
   - `Metadata`：Read-only（自动勾选）
4. 生成后复制保存。

也可以使用 Classic PAT，需勾选 `repo` 与 `workflow`，但它能访问你账号下的所有仓库，不推荐。

### 第 3 步（可选）：配置私有源码仓库的访问令牌

如果 FFmpeg 源码仓库是**公开**的（例如官方 `https://github.com/FFmpeg/FFmpeg`），跳过此步。

如果是**私有**仓库：

1. 再创建一个 Fine-grained PAT，**Repository access** 只选该私有 FFmpeg 仓库，权限只给 `Contents: Read-only`。
2. 打开 Fork 仓库的 **Settings → Secrets and variables → Actions → New repository secret**。
3. Name 填 `SOURCE_PAT`，Secret 填刚才的 PAT，保存。

工作流会以 Secret 的形式读取它（日志中自动打码）；未配置时使用工作流自带的 `GITHUB_TOKEN`，只能拉取公开仓库。

### 第 4 步：在网页上提交编译

打开第 1 步得到的 Pages 地址，按表单填写：

| 字段 | 说明 | 示例 |
|---|---|---|
| GitHub PAT | 第 2 步创建的令牌 | `github_pat_xxx` |
| FFmpeg Git 仓库地址 | GitHub 仓库，HTTPS 或 SSH 写法均可 | `https://github.com/FFmpeg/FFmpeg` |
| 源码分支 / tag / commit | 可选；commit 需填完整 40 位 SHA | `n7.1`、`release/7.1` |
| 目标平台 | `Linux` / `macOS` / `Windows` / `全部平台` | `Linux` |
| 目标指令集 | 选项随平台变化，见下方对照表 | `x86_64` |
| 打包格式 | `tar.gz` 或 `zip` | `zip` |
| configure 编译参数 | 空格分隔，可先选“常用模板”再点“应用模板” | `--disable-debug --disable-doc --enable-gpl` |

点击 **触发编译**。页面会：

1. 校验 PAT 对当前仓库有写权限；
2. 触发工作流并立即定位到对应的运行记录；
3. 每 10 秒轮询一次状态（网络异常会自动退避重试），在“当前任务状态”中显示进度。

### 第 5 步：查看进度与下载产物

- **当前任务状态**：点击“展开日志摘要”可查看每个 Job / Step 的耗时与结果；点击“查看 Actions 日志”跳转完整日志。
- 编译完成后会出现：
  - **Artifact 链接**：跳转到 Actions 运行页面下载（需登录 GitHub，默认保留 90 天）；
  - **Draft Release 链接**及其中的每个资源文件，外加 `SHA256SUMS.txt` 校验文件。
- Draft Release 只有你自己可见。确认无误后，在 Release 页面点击 **Edit → Publish release** 即可公开发布。
- **最近任务**：点击“刷新任务状态”查看仓库最近 10 次编译。
- **本地历史记录**：保存在浏览器 `localStorage`，换浏览器或清缓存后会丢失。

### 第 6 步：使用编译产物

解压后的目录结构：

```text
bin/            ffmpeg、ffprobe（以及 Windows 下的 DLL）
lib/            静态库 / 共享库、pkgconfig/*.pc
include/        头文件
share/          示例与 man 页（取决于 configure 参数）
BUILDINFO.txt   源码仓库、ref、commit、编译器、configure 参数
```

- **直接运行**：`./bin/ffmpeg -version`。共享库构建已设置 rpath（Linux 为 `$ORIGIN/../lib`，macOS 为 `@loader_path/../lib`），不需要设置 `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`。
- **macOS 首次运行**提示“无法验证开发者”时，执行 `xattr -dr com.apple.quarantine <解压目录>`。
- **作为开发库使用**：`export PKG_CONFIG_PATH=<解压目录>/lib/pkgconfig`，`.pc` 文件中的路径已改为相对位置，放在任意目录都能正确解析。
- **Windows**：`bin/` 中已附带 `libwinpthread-1.dll` 等 MinGW 运行时，可脱离 MSYS2 运行。

### 也可以不用网页

在 Fork 仓库的 **Actions → build-ffmpeg → Run workflow** 中直接填写同样的参数即可；`release_tag` 需自行填写一个唯一值（只允许字母、数字、`.`、`_`、`-`）。

## 平台与指令集对照表

| 平台    | 指令集    | Runner                       | 说明                                  |
|---------|-----------|------------------------------|---------------------------------------|
| linux   | x86_64    | ubuntu-latest                | 原生编译                              |
| linux   | x86       | ubuntu-latest                | `i686-linux-gnu` 交叉编译             |
| linux   | arm64     | ubuntu-24.04-arm             | 原生 ARM runner                       |
| linux   | armv7     | ubuntu-latest                | `arm-linux-gnueabihf` 交叉编译        |
| macos   | x86_64    | macos-15-intel               | 原生编译（最低系统 macOS 11）         |
| macos   | arm64     | macos-15                     | 原生编译（最低系统 macOS 11）         |
| macos   | universal | macos-15-intel + macos-15    | 分别编译后 lipo 合并（含静态库）      |
| windows | x86_64    | windows-latest               | MSYS2 MINGW64                         |
| windows | x86       | windows-latest               | MSYS2 MINGW32（实验性，见已知限制）   |
| windows | arm64     | windows-11-arm               | MSYS2 CLANGARM64，原生 ARM runner     |

> - 选择“全部平台”时，Linux / macOS / Windows 三平台同时并行构建；不适用的组合（如 macOS + x86）会被跳过。
> - Linux / Windows 选择 `universal` 时按 x86_64 构建。
> - 部分平台失败时，成功的产物仍会发布到 Draft Release。

## configure 参数说明

- 参数以空格分隔，仅允许 `[-+./:=,@%A-Za-z0-9_]` 字符，含 `; & | $ > \`` 或空格的值会被拒绝（因此 `--extra-cflags="-O3 -march=native"` 这类带空格的参数无法使用）。
- 工作流会在你的参数**之前**自动注入交叉编译参数和 `--cc=ccache ...`；如需覆盖，直接写同名参数即可（后出现者生效）。
- 页面内置模板：

| 模板 | 参数 |
|---|---|
| 精简常用构建 | `--disable-debug --disable-doc --enable-gpl` |
| 共享库 + GPL | `--disable-debug --disable-doc --enable-gpl --enable-version3 --enable-shared` |
| 静态库优先 | `--disable-debug --disable-doc --enable-gpl --enable-version3 --enable-static --disable-shared` |

- 运行环境只安装了编译 FFmpeg 本体所需的工具链，**没有安装 x264、x265、libvpx 等第三方库**；`--enable-libx264` 这类参数会在 configure 阶段失败。需要时可在 Fork 中修改 `scripts/install-deps.sh` 与工作流里的 MSYS2 包列表。

## 编译流程

1. Pages 前端识别当前仓库与默认分支，校验 PAT 的写权限。
2. 调用 `workflow_dispatch`（带 `return_run_details`，直接拿到运行 ID），传入：
   `source_repository`、`source_ref`、`target_platform`、`target_arch`、`package_format`、`configure_options`、`release_tag`。
3. **setup**：校验 release tag、configure 参数与源码仓库地址，生成构建矩阵。
4. **build**（矩阵并行）：
   - `actions/checkout` 拉取源码（私有仓库使用 `SOURCE_PAT` Secret，`persist-credentials: false`）；
   - 恢复 ccache 缓存，安装依赖（Linux/macOS 用脚本，Windows 用 `msys2/setup-msys2`）；
   - `scripts/build-ffmpeg.sh`：configure → make → make install → 修正 rpath / install name / `.pc` 路径 → 打包 Windows 运行时 DLL → `ffmpeg -version` 冒烟测试（交叉编译跳过）→ 写入 `BUILDINFO.txt` → 打包；
   - 上传 Artifact。
5. **lipo**（仅 macOS universal）：合并两个架构的可执行文件、动态库与静态库。
6. **release**：汇总所有成功的产物，生成 `SHA256SUMS.txt`，一次性创建 Draft Release。

## 安全设计

- 网页 PAT 只保存在浏览器内存中，只用于调用 GitHub API，**不作为工作流输入传递**，因此不会出现在 Actions 日志中；本地历史记录也不含 PAT。
- 私有源码仓库的令牌以 Repository Secret（`SOURCE_PAT`）形式存放，GitHub 会在日志中自动打码；源码检出后不保留凭证。
- 前端会校验 PAT 对当前仓库有写权限；GitHub 本身也只允许有写权限的用户触发 `workflow_dispatch`。
- `configure` 参数只允许安全字符集，release tag 只允许 `[A-Za-z0-9._-]`，源码地址只接受 `github.com` 仓库。
- 工作流输入一律通过环境变量传给脚本，不直接拼接进 shell 命令。

## 已知限制

- **Linux 产物的 glibc 版本**：在 `ubuntu-latest` 上编译，生成的二进制依赖较新的 glibc，可能无法在老旧发行版（如 CentOS 7、Ubuntu 20.04）上运行。需要兼容老系统时，建议使用 `--enable-static --disable-shared` 并在 Fork 中改为在旧版容器内编译。
- **Linux 交叉编译**（x86 / armv7）不会运行冒烟测试，也没有为目标架构准备第三方库。
- **Windows x86（MINGW32）**：MSYS2 正在逐步移除 32 位环境，相关软件包可能随时不可用。
- **Windows armv7** 已移除：MSYS2 不再提供可用的 32 位 ARM 环境。
- **macOS Intel**：GitHub 预计在 2027 年秋随 macOS 15 镜像退役而停止提供 Intel runner，届时 macOS x86_64 / universal 需改为在 arm64 上交叉编译。
- 页面需以 `https://<owner>.github.io/<repo>/` 形式访问才能自动识别仓库；绑定自定义域名后无法识别。

## 可扩展方向

- 在 Pages 中配置并保存多套 configure 预设
- 预装常用第三方编解码库（x264、x265、libvpx、libopus 等）
- 构建完成后通过 webhook 或邮件通知

## 许可证

本仓库已附带 **MIT License**，支持任意个人或商用 Fork、自定义和再分发。
