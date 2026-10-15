# FFmpeg Auto Builder

基于 **GitHub Pages + GitHub Issues + GitHub Actions** 的 FFmpeg 在线自动编译模板仓库。任何人 Fork 后，只需开启 Actions、Issues 和 Pages，即可获得一套纯 GitHub 生态、无需第三方后端、**网页上无需输入任何令牌**的可视化编译工具。

## 功能概览

- 网页填写源码仓库、分支/tag/commit、目标平台、指令集、打包格式和 configure 参数，一键生成预填好的编译 Issue。
- 在 GitHub 上提交 Issue 即触发编译，身份由你的 GitHub 登录状态保证，网页不接触任何令牌。
- 只执行仓库所有者 / 协作者提交的编译 Issue，其他人提交的 Issue 不会消耗 Actions 额度。
- 编译开始、完成、失败都会自动在 Issue 中评论，并附 Draft Release 与 Artifact 链接；GitHub 会按你的通知设置推送提醒。
- 支持公有 FFmpeg 仓库；配置 `SOURCE_PAT` Secret 后支持私有 FFmpeg Fork。
- 支持 Linux / macOS / Windows 三平台并行构建，macOS 可生成 x86_64 + arm64 通用（Universal）二进制。
- Linux 支持 x86、arm64、armv7；Windows 通过 MSYS2 支持 x86_64、x86、arm64。
- ccache 增量编译、冒烟测试、统一发布一个 Draft Release（附 `SHA256SUMS.txt`）。
- 产物可直接解压使用：共享库构建自动修正 rpath / install name，`.pc` 文件改为相对路径，Windows 包自动附带 MinGW 运行时 DLL，包内附 `BUILDINFO.txt`。
- 网页展示最近的编译记录、运行状态和 Job/Step 日志摘要。
- 代码中不硬编码仓库名、用户名、密钥，Fork 后无需改代码即可使用。

## 目录结构

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/build.yml  # 编译请求的 Issue 表单
│   └── workflows/build.yml       # 编译流水线（setup → build matrix → lipo → release）
├── docs/                         # GitHub Pages 前端（index.html / app.js / configure.js / styles.css）
└── scripts/
    ├── common.sh                 # 公共工具函数（仓库地址解析、参数过滤等）
    ├── parse-issue.py            # 从 Issue 正文解析编译参数
    ├── resolve-params.sh         # 校验参数、生成 release tag 与构建矩阵
    ├── install-deps.sh           # Linux / macOS 依赖安装（apt / brew）
    ├── build-ffmpeg.sh           # 编译、修正产物路径、冒烟测试并打包
    └── lipo-universal.sh         # 将 x86_64 + arm64 包合并为 macOS 通用二进制
```

## 使用教程

### 第 1 步：Fork 并开启功能

1. 点击右上角 **Fork**，把本仓库复制到你自己的账号（或你有写权限的组织）下。
2. **开启 Actions**：打开 Fork 仓库的 **Actions** 页面，点击 **I understand my workflows, go ahead and enable them**（Fork 仓库默认禁用 Actions）。
3. **开启 Issues**：打开 **Settings → General → Features**，勾选 **Issues**（Fork 仓库默认关闭 Issues）。
4. **开启 Pages**：打开 **Settings → Pages**，在 **Build and deployment** 中选择：
   - **Source**：`Deploy from a branch`
   - **Branch**：默认分支，**Folder**：`/docs`
5. 保存后等待 1～2 分钟，页面顶部会显示 Pages 地址，形如 `https://<你的用户名>.github.io/<仓库名>/`。Custom domain 保持留空即可。

### 第 2 步（可选）：配置私有源码仓库的访问令牌

如果 FFmpeg 源码仓库是**公开**的（例如官方 `https://github.com/FFmpeg/FFmpeg`），跳过此步。

如果是**私有**仓库：

1. 打开 https://github.com/settings/personal-access-tokens/new 创建一个 Fine-grained PAT：
   - **Repository access** 选择 **Only select repositories**，只勾选该私有 FFmpeg 仓库；
   - **Repository permissions** 中只给 `Contents: Read-only`。
2. 打开 Fork 仓库的 **Settings → Secrets and variables → Actions → New repository secret**。
3. Name 填 `SOURCE_PAT`，Secret 填刚才的 PAT，保存。

工作流以 Secret 形式读取它（日志中自动打码）；未配置时使用工作流自带的 `GITHUB_TOKEN`，只能拉取公开仓库。

### 第 3 步：在网页上填写参数

打开第 1 步得到的 Pages 地址。页面顶部会显示识别到的仓库，以及 Issues 是否已开启。按表单填写：

| 字段 | 说明 | 示例 |
|---|---|---|
| FFmpeg Git 仓库地址 | GitHub 仓库，HTTPS 或 SSH 写法均可 | `https://github.com/FFmpeg/FFmpeg` |
| 源码分支 / tag / commit | 可选；commit 需填完整 40 位 SHA | `n7.1`、`release/7.1` |
| 目标平台 | `Linux` / `macOS` / `Windows` / `全部平台` | `Linux` |
| 目标指令集 | 选项随平台变化，见下方对照表 | `x86_64` |
| 打包格式 | `tar.gz` 或 `zip` | `zip` |
| 编译参数 | 用可视化控件选择构建类型、链接方式、许可证、程序与库、功能特性和组件，也可在自定义参数中粘贴已有命令行；下方实时显示最终 configure 参数（详见“configure 参数说明”） | Release + 静态 + GPL |

点击 **在 GitHub 上提交编译**，页面会先在本地校验参数，然后在新标签页打开 GitHub 的新建 Issue 页面，所有参数都已填好。

### 第 4 步：在 GitHub 上提交 Issue

1. 确认登录的是仓库所有者（或协作者）账号，检查一下参数。
2. 点击 **Submit new issue**。
3. 几秒内工作流就会启动，并在 Issue 中回复 **🚀 已开始编译**，附带参数表和运行进度链接。

> 也可以不经过网页：在仓库 **Issues → New issue** 中选择 **FFmpeg 编译** 模板直接填写。

### 第 5 步：查看进度与下载产物

- **Issue 评论**：编译结束后会收到 **✅ 编译完成**、**⚠️ 部分目标编译失败** 或 **❌ 编译失败** 评论，内含：
  - **Draft Release** 链接（含所有产物与 `SHA256SUMS.txt`）。草稿仅仓库所有者和协作者可见，确认无误后在 Release 页面点击 **Publish release** 即可公开；
  - **运行详情**链接，可在页面底部下载 Artifact（需登录 GitHub，默认保留 90 天）；
  - 每个平台任务的结果表。
- 编译成功后 Issue 会自动关闭；失败时保持打开，方便排查。
- **网页上的“编译记录”**：列出最近 20 个编译 Issue 及其运行状态，可展开 Job/Step 日志摘要。有任务进行中时每 10 分钟自动刷新一次，也可随时点击“刷新”。网页未登录访问 GitHub API，每小时限 60 次请求，超出后稍等再刷新即可。
- 参数校验失败（例如平台写错、configure 参数含非法字符）时，工作流会在 Issue 中回复错误原因并关闭该 Issue，修正后重新提交一个新的即可。

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

### 备用方式：手动运行工作流

在仓库 **Actions → build-ffmpeg → Run workflow** 中填写同样的参数即可，结果只出现在 Actions 运行页面和 Releases 中，不会有 Issue 评论。

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

- 参数以空格或换行分隔，仅允许 `[-+./:=,@%A-Za-z0-9_]` 字符，含 `; & | $ > \`` 或空格的值会被拒绝（因此 `--extra-cflags="-O3 -march=native"` 这类带空格的参数无法使用）。
- 工作流会在你的参数**之前**自动注入交叉编译参数和 `--cc=ccache ...`；如需覆盖，直接写同名参数即可（后出现者生效）。
### 网页上的可视化参数

网页把常用的 configure 开关做成了可视化控件，按 **构建类型 / 链接方式 / 许可证 → 程序与库 → 功能特性 → 组件 → 自定义参数** 的顺序生成参数，并实时显示“最终 configure 参数”（可一键复制）。当前配置会保存在浏览器本地，下次打开自动恢复；“恢复默认”可重置。

| 分组 | 选项 | 对应参数 |
|---|---|---|
| 构建类型 | **Release**（默认）／RelWithDebInfo／Debug | `--disable-debug`／`--disable-stripping`／`--enable-debug=3 --disable-optimizations --disable-stripping` |
| 链接方式 | **静态**（默认）／共享／静态 + 共享 | `--enable-static --disable-shared`／`--enable-shared --disable-static`／两者都启用 |
| 许可证 | LGPL／**GPL**（默认）／GPL v3 | 不加参数／`--enable-gpl`／`--enable-gpl --enable-version3` |
| 程序与库 | ffmpeg、ffprobe、libavdevice、libavfilter、libswscale、libswresample、文档 | 取消勾选即 `--disable-<名称>`（文档默认不生成：`--disable-doc`） |
| 功能特性 | 汇编优化、硬件加速、网络协议、自动探测系统库、体积优化、PIC | `--disable-asm`、`--disable-hwaccels`、`--disable-network`、`--disable-autodetect`、`--enable-small`、`--enable-pic` |
| 组件 | **全部组件**（默认）／精简 | 精简模式：`--disable-everything` + 按类别勾选的 `--enable-decoder=...`、`--enable-demuxer=...` 等 |

- **组件精简**：可按解码器、编码器、解封装、封装、解析器、比特流滤镜、协议、滤镜分别勾选，每类都有“全选 / 清空 / 常用”快捷按钮。适合嵌入播放器、移动端等对体积敏感的场景。
- **许可证与组件联动**：FFmpeg 中部分组件仅限 GPL（如 `hqdn3d`、`delogo`、`eq`、`cropdetect`、`mpdecimate` 滤镜），在组件列表中带有 **GPL** 标记。选择 LGPL 时它们会变为不可选，且不会写入参数（configure 本身也会自动排除）；切回 GPL 后之前的勾选自动恢复。
- **Debug 构建**：FFmpeg 依赖编译器的死代码消除，不支持 `-O0`，因此 Debug 仍会保留最低限度的优化。
- **自定义参数自动同步**：在“高级 → 自定义参数”中可直接粘贴已有的 configure 参数（含 `./configure` 也可以）。输入框失去焦点后，能由上方控件表达的参数（如 `--enable-shared`、`--disable-avfilter`、`--disable-everything --enable-decoder=h264`）会自动同步到对应控件，其余保留在输入框中。同步以当前选择为基础，且保证同步前后最终参数完全等价；若无法等价表达则保持原样。
- **自定义参数**追加在最后，可覆盖上面任何选项（同一开关以后出现的为准）；`--enable-decoder=` 这类组件参数可以多次出现。
- 鼠标悬停在选项上可查看说明和对应参数。
- 页面会实时提示：关闭 libavfilter 时 ffmpeg 程序不会生成、精简模式未选协议、使用 `--enable-lib*` 第三方库、`--enable-nonfree` 不可再分发等。
- 不允许指定 `--prefix`：安装路径由编译流程管理，网页与工作流都会拒绝。

- 运行环境只安装了编译 FFmpeg 本体所需的工具链，**没有安装 x264、x265、libvpx 等第三方库**；`--enable-libx264` 这类参数会在 configure 阶段失败。需要时可在 Fork 中修改 `scripts/install-deps.sh` 与 `scripts/resolve-params.sh` 里的 MSYS2 包列表。

## 编译流程

1. 网页把参数编码进新建 Issue 的链接（`/issues/new?template=build.yml&...`），由你在 GitHub 上确认提交。
2. `issues: opened` 事件触发工作流。**setup** 任务：
   - 只处理标题以 `[build]` 开头、且提交人为仓库 `OWNER` / `MEMBER` / `COLLABORATOR` 的 Issue，其余直接跳过；
   - `scripts/parse-issue.py` 解析 Issue 正文，`scripts/resolve-params.sh` 校验平台、指令集、打包格式、源码地址、ref 与 configure 参数，生成 release tag 和构建矩阵；
   - 校验失败时在 Issue 中回复错误原因并关闭；成功时打上 `build` 标签并回复“已开始编译”。
3. **build**（矩阵并行）：
   - `actions/checkout` 拉取源码（私有仓库使用 `SOURCE_PAT` Secret，`persist-credentials: false`）；
   - 恢复 ccache 缓存，安装依赖（Linux/macOS 用脚本，Windows 用 `msys2/setup-msys2`）；
   - `scripts/build-ffmpeg.sh`：configure → make → make install → 修正 rpath / install name / `.pc` 路径 → 打包 Windows 运行时 DLL → `ffmpeg -version` 冒烟测试（交叉编译跳过）→ 写入 `BUILDINFO.txt` → 打包；
   - 上传 Artifact。
4. **lipo**（仅 macOS universal）：合并两个架构的可执行文件、动态库与静态库。
5. **release**：汇总所有成功的产物，生成 `SHA256SUMS.txt`，一次性创建 Draft Release，然后在 Issue 中回复结果，成功则关闭 Issue。

## 安全设计

- **网页不处理任何令牌**：触发编译依靠你在 github.com 上的登录身份提交 Issue，网页只读取公开 API，不存在令牌被仿冒页面骗取或泄露的问题。
- **只执行可信用户的请求**：公开仓库任何人都能提交 Issue，工作流只处理仓库所有者、组织成员和协作者提交的编译 Issue。
- **私有源码令牌放在 Secret 中**：`SOURCE_PAT` 只在工作流内使用，日志自动打码，源码检出后不保留凭证。
- **输入严格校验**：Issue 内容视为不可信数据，全部通过环境变量传给脚本，从不直接拼接进 shell 命令；平台、指令集、格式只接受固定取值，configure 参数只允许安全字符集，源码地址只接受 `github.com` 仓库。
- 公开仓库的编译 Issue 对所有人可见（包括 configure 参数）。如不希望公开，可将 Fork 设为私有仓库，此时网页的“编译记录”无法读取，请直接在 GitHub 上查看 Issues。

## 已知限制

- **Linux 产物的 glibc 版本**：在 `ubuntu-latest` 上编译，生成的二进制依赖较新的 glibc，可能无法在老旧发行版（如 CentOS 7、Ubuntu 20.04）上运行。需要兼容老系统时，建议使用 `--enable-static --disable-shared` 并在 Fork 中改为在旧版容器内编译。
- **Linux 交叉编译**（x86 / armv7）不会运行冒烟测试，也没有为目标架构准备第三方库。
- **Windows x86（MINGW32）**：MSYS2 正在逐步移除 32 位环境，相关软件包可能随时不可用。
- **Windows armv7** 已移除：MSYS2 不再提供可用的 32 位 ARM 环境。
- **macOS Intel**：GitHub 预计在 2027 年秋随 macOS 15 镜像退役而停止提供 Intel runner，届时 macOS x86_64 / universal 需改为在 arm64 上交叉编译。
- 页面需以 `https://<owner>.github.io/<repo>/` 形式访问才能自动识别仓库；绑定自定义域名后无法识别。
- 修改已提交 Issue 的内容不会重新触发编译，如需调整参数请提交新的 Issue。

## 可扩展方向

- 在 Pages 中配置并保存多套 configure 预设
- 预装常用第三方编解码库（x264、x265、libvpx、libopus 等）

## 许可证

本仓库已附带 **MIT License**，支持任意个人或商用 Fork、自定义和再分发。
