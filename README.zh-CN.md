# FFmpeg Auto Builder

[English](README.md) | 简体中文

基于 **GitHub Pages + GitHub Issues + GitHub Actions** 的 FFmpeg 在线自动编译模板仓库。任何人 Fork 后，只需开启 Actions、Issues 和 Pages，即可获得一套纯 GitHub 生态、无需第三方后端、**网页上无需输入任何令牌**的可视化编译工具。

**[打开网页 →](../../deployments/github-pages)**（在任何 Fork 中都会打开该 Fork 自己的 Pages 部署记录，点击其中的 **View deployment** 即可；也可以使用侧栏的 **Deployments**。）

## 功能概览

- 网页填写源码仓库、分支/tag/commit、打包格式、目标平台、指令集和 configure 参数，一键生成预填好的编译 Issue。
- 在 GitHub 上提交 Issue 即触发编译，身份由你的 GitHub 登录状态保证，网页不接触任何令牌。
- 只执行仓库所有者 / 协作者提交的编译 Issue，其他人提交的 Issue 不会消耗 Actions 额度。
- 编译开始、完成、失败都会自动在 Issue 中评论，并附 Draft Release 与 Artifact 链接；GitHub 会按你的通知设置推送提醒。
- 支持公有 FFmpeg 仓库；配置 `SOURCE_PAT` Secret 后支持私有 FFmpeg Fork。
- 支持 Linux / macOS / Windows 的 x86_64、x86、arm64、armv7，macOS 可生成 x86_64 + arm64 通用（Universal）二进制。
- 参照官方预编译版本的做法，**从源码编译常用第三方库并静态链接**（x264、x265、libvpx、dav1d、SVT-AV1、libaom、Opus、LAME、Vorbis、WebP、zimg、SoX 重采样、libass），每个库都可以在网页上开关。
- Linux x86_64 / arm64 产物兼容 glibc 2.28+（RHEL 8、Debian 10、Ubuntu 20.04 及更新版本）；Windows x86_64 / x86 / arm64 用 llvm-mingw 交叉编译，生成不依赖额外 DLL 的可执行文件；macOS 支持 11.0+；Linux x86 / armv7 兼容 glibc 2.31+（Debian 11、Ubuntu 20.04 及更新版本）。
- ccache 增量编译、冒烟测试、统一发布一个 Draft Release（附 `SHA256SUMS.txt`）。
- 打包格式支持 `tar.gz`、`zip` 和可用于 C++ / C# 项目的 **NuGet 包**；一个 NuGet 包可以包含该平台任意勾选的多个指令集。
- 产物可直接解压使用：共享库构建自动修正 rpath / install name，`.pc` 文件改为相对路径，Windows 可执行文件不依赖额外 DLL，包内附 `BUILDINFO.txt`。
- 网页展示最近的编译记录、运行状态和 Job/Step 日志摘要。
- 网页支持 **English / 简体中文 / 日本語** 切换（默认跟随浏览器语言），生成的 Issue 以及工作流在 Issue 中的回复都会使用同一语言。
- 代码中不硬编码仓库名、用户名、密钥，Fork 后无需改代码即可使用。

## 目录结构

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/           # 编译请求的 Issue 表单（build.yml 英文 / build-zh-CN.yml / build-ja.yml）
│   └── workflows/
│       ├── build.yml             # 编译流水线（setup → build matrix → lipo → release）
│       └── deps.yml              # 预先编译并缓存第三方库
├── deps/                         # 每个第三方库一个编译脚本（版本、下载地址、SHA256、编译步骤）
├── docs/                         # GitHub Pages 前端（index.html / app.js / configure.js / i18n.js / styles.css）
│   └── targets.json              # 编译目标：平台、指令集、runner、约束条件
└── scripts/
    ├── common.sh                 # 公共工具函数（仓库地址解析、参数过滤等）
    ├── parse-issue.py            # 从 Issue 正文解析编译参数并识别语言
    ├── issue-comment.sh          # 按 Issue 语言回复开始 / 校验失败 / 编译结果
    ├── resolve-params.sh         # 校验参数、生成 release tag 与构建矩阵
    ├── targets.py                # 读取 docs/targets.json：参数校验、构建矩阵
    ├── install-deps.sh           # 安装编译工具（platform_install）
    ├── toolchain.sh              # 工具链配置，第三方库与 FFmpeg 共用（platform_toolchain）
    ├── platforms/<平台>.sh        # 各平台的编译工具与工具链
    ├── build-deps.sh             # 把 deps/*.sh 编译成静态库
    ├── build-ffmpeg.sh           # 编译、修正产物路径、冒烟测试并打包
    ├── pack-nuget.py             # 将各指令集的压缩包合并为一个 NuGet 包
    └── merge-slices.sh           # 用 lipo 把单指令集的包合并为通用二进制
```

## 使用教程

### 第 1 步：Fork 并开启功能

1. 点击右上角 **Fork**，把本仓库复制到你自己的账号（或你有写权限的组织）下。
2. **开启 Actions**：打开 Fork 仓库的 **Actions** 页面，点击 **I understand my workflows, go ahead and enable them**（Fork 仓库默认禁用 Actions）。
3. **开启 Issues**：打开 **Settings → General → Features**，勾选 **Issues**（Fork 仓库默认关闭 Issues）。
4. **开启 Pages**：打开 **Settings → Pages**，在 **Build and deployment** 中选择：
   - **Source**：`Deploy from a branch`
   - **Branch**：默认分支，**Folder**：`/docs`
5. 保存后等待 1～2 分钟，页面顶部会显示 Pages 地址，形如 `https://<你的用户名>.github.io/<仓库名>/`。Custom domain 保持留空即可。之后也可以从仓库侧栏的 **Deployments → github-pages** 或本 README 顶部的“打开网页”链接进入；在首页 **About** 旁的齿轮中勾选 **Use your GitHub Pages website**，仓库首页就会直接显示该地址。

### 第 2 步（可选）：配置私有源码仓库的访问令牌

如果 FFmpeg 源码仓库是**公开**的（例如官方 `https://github.com/FFmpeg/FFmpeg`），跳过此步。

如果是**私有**仓库：

1. 打开 https://github.com/settings/personal-access-tokens/new 创建一个 Fine-grained PAT：
   - **Repository access** 选择 **Only select repositories**，勾选要编译的私有 FFmpeg 仓库（可多选）；
   - **Repository permissions** 中只给 `Contents: Read-only`。
2. 打开 Fork 仓库的 **Settings → Secrets and variables → Actions → New repository secret**。
3. Name 填 `SOURCE_PAT`，Secret 填刚才的 PAT，保存。

工作流以 Secret 形式读取它（日志中自动打码）；未配置时使用工作流自带的 `GITHUB_TOKEN`，只能拉取公开仓库（即使是同账号下的私有仓库也需要配置）。

### 第 3 步：在网页上填写参数

打开第 1 步得到的 Pages 地址。页面顶部会显示识别到的仓库，以及 Issues 是否已开启；右上角可切换界面语言（English / 简体中文 / 日本語），提交的 Issue 和工作流回复会跟随该语言。按表单填写：

| 字段 | 说明 | 示例 |
|---|---|---|
| FFmpeg Git 仓库地址 | GitHub 仓库，HTTPS 或 SSH 写法均可 | `https://github.com/FFmpeg/FFmpeg` |
| 源码分支 / tag / commit | 可选；commit 需填完整 40 位 SHA | `n7.1`、`release/7.1` |
| 打包格式 | `tar.gz`、`zip` 或 `NuGet (.nupkg)`（见“NuGet 包”） | `zip` |
| 目标平台 | `Linux` / `macOS` / `Windows` | `Linux` |
| 目标指令集 | 选项随平台和打包格式变化，见下方对照表 | `x86_64` |
| 编译参数 | 用可视化控件选择构建类型、链接方式、许可证、程序与库、功能特性和组件，必要时补充自定义参数；下方实时显示最终 configure 参数（详见“configure 参数说明”） | Release + 静态 + GPL |

点击 **在 GitHub 上提交编译**，页面会先在本地校验参数，然后在新标签页打开 GitHub 的新建 Issue 页面，所有参数都已填好。

### 第 4 步：在 GitHub 上提交 Issue

1. 确认登录的是仓库所有者（或协作者）账号，检查一下参数。
2. 点击 **Submit new issue**。
3. 几秒内工作流就会启动，并在 Issue 中回复 **🚀 已开始编译**，附带参数表和运行进度链接。

> 也可以不经过网页：在仓库 **Issues → New issue** 中选择 **FFmpeg Build** / **FFmpeg 编译** / **FFmpeg ビルド** 任一模板直接填写，工作流会用该模板的语言回复。

### 第 5 步：查看进度与下载产物

- **Issue 评论**：编译结束后会收到 **✅ 编译完成**、**⚠️ 部分目标编译失败** 或 **❌ 编译失败** 评论，内含：
  - **Draft Release** 链接（含所有产物与 `SHA256SUMS.txt`）。草稿仅仓库所有者和协作者可见，确认无误后在 Release 页面点击 **Publish release** 即可公开；
  - **运行详情**链接，可在页面底部下载 Artifact（需登录 GitHub，默认保留 90 天）；
  - 每个平台任务的结果表。
- 编译成功后 Issue 会自动关闭；失败时保持打开，方便排查。
- **网页上的“编译记录”**：列出最近 20 个编译 Issue 及其运行状态，可展开 Job/Step 日志摘要。有任务进行中时每 10 分钟自动刷新一次，也可随时点击“刷新”。网页未登录访问 GitHub API，每小时限 60 次请求，超出后稍等再刷新即可。
- 参数校验失败（例如平台写错、configure 参数含非法字符）时，工作流会在 Issue 中回复错误原因并关闭该 Issue，修正后重新提交一个新的即可。

### 第 6 步：使用编译产物

压缩包命名为 `ffmpeg-<平台>-<指令集>-<许可证>-<编译编号>.zip`（或 `.tar.gz`），许可证按 configure 参数取 `gpl`、`lgpl`、`gplv3`、`lgplv3` 或 `nonfree`，如 `ffmpeg-linux-x86_64-gpl-20261016t080000-i42.tar.gz`。解压后的目录结构：

```text
bin/            ffmpeg、ffprobe（以及 Windows 下的 DLL）
lib/            静态库 / 共享库、pkgconfig/*.pc
                （Windows 共享库构建：导入库 avcodec.lib 等及 .def 文件）
include/        头文件
share/          示例与 man 页（取决于 configure 参数）
BUILDINFO.txt   源码仓库、ref、commit、编译器、configure 参数
```

- **直接运行**：`./bin/ffmpeg -version`。共享库构建已设置 rpath（Linux 为 `$ORIGIN/../lib`，macOS 为 `@loader_path/../lib`），不需要设置 `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`。
- **macOS 首次运行**提示“无法验证开发者”时，执行 `xattr -dr com.apple.quarantine <解压目录>`。
- **作为开发库使用**：`export PKG_CONFIG_PATH=<解压目录>/lib/pkgconfig`，`.pc` 文件中的路径已改为相对位置，放在任意目录都能正确解析。
- **Windows**：静态构建只有 `ffmpeg.exe` / `ffprobe.exe` 两个文件，只依赖 Windows 系统 DLL（Windows 10+）。共享库构建的 `avcodec-63.dll` 等在 `bin/`，导入库 `avcodec.lib` 等在 `lib/`，MSVC、clang-cl 和 MinGW 都能直接链接。静态构建的静态库（`libavcodec.a` 等）由 MinGW 工具链生成，需要用 MinGW 或 clang 链接；MSVC 项目请使用共享库构建。
- **库文件命名**：Linux 为 `libavcodec.so` → `libavcodec.so.63` → `libavcodec.so.63.x.y`（符号链接，SONAME 为 `libavcodec.so.63`）；macOS 为 `libavcodec.dylib` → `libavcodec.63.dylib` → `libavcodec.63.x.y.dylib`（install name 为 `@rpath/libavcodec.63.dylib`）。

### 备用方式：手动运行工作流

在仓库 **Actions → build-ffmpeg → Run workflow** 中填写同样的参数即可，结果只出现在 Actions 运行页面和 Releases 中，不会有 Issue 评论。

## 平台与指令集对照表

| 平台    | 指令集    | Runner                       | 说明                                  |
|---------|-----------|------------------------------|---------------------------------------|
| linux   | x86_64    | ubuntu-latest，manylinux_2_28 容器 | 原生编译，glibc 2.28+，含第三方库 |
| linux   | arm64     | ubuntu-24.04-arm，manylinux_2_28 容器 | 原生编译，glibc 2.28+，含第三方库 |
| linux   | x86       | ubuntu-latest，Ubuntu 20.04 容器 | `i686-linux-gnu` 交叉编译（SSE2），glibc 2.31+，含第三方库 |
| linux   | armv7     | ubuntu-latest，Ubuntu 20.04 容器 | `arm-linux-gnueabihf` 交叉编译（硬浮点），glibc 2.31+，含第三方库 |
| macos   | x86_64    | macos-15-intel               | 原生编译（最低 macOS 11），含第三方库 |
| macos   | arm64     | macos-15                     | 原生编译（最低 macOS 11），含第三方库 |
| macos   | universal | macos-15-intel + macos-15    | 分别编译后 lipo 合并（含静态库）      |
| windows | x86_64    | ubuntu-latest                | llvm-mingw 交叉编译，含第三方库       |
| windows | x86       | ubuntu-latest                | llvm-mingw 交叉编译（SSE2），含第三方库 |
| windows | arm64     | ubuntu-latest                | llvm-mingw 交叉编译，含第三方库       |

> - `universal`（macOS，`tar.gz` / `zip`）把 x86_64 和 arm64 合并为通用二进制。
> - 打包格式为 NuGet 时，指令集变为多选：勾选的指令集并行编译，并打进同一个 NuGet 包（NuGet 下不提供 `universal`，请同时勾选 x86_64 和 arm64）。
> - 部分指令集失败时，成功的产物仍会发布到 Draft Release。

## NuGet 包

**打包格式选择 NuGet** 时，Release 中是一个 `.nupkg`，而不是压缩包；勾选需要包含的指令集，它们会放进同一个包中。NuGet 包固定使用**共享库**（网页会锁定链接方式，工作流也会追加 `--enable-shared --disable-static`）。

- **包 ID**：`<仓库所有者>.FFmpeg.<许可证>.<平台>`。许可证为 `GPL`、`LGPL`、`GPLv3`、`LGPLv3` 或 `NonFree`；单一指令集时平台为 RID（`win-x64`、`linux-arm` 等），多个指令集时为平台名（`win` / `linux` / `osx`）。如 `IOL0ol1.FFmpeg.LGPL.win-x64`、`IOL0ol1.FFmpeg.GPL.linux`。**版本**：源码 `RELEASE` 文件中的 FFmpeg 版本加上工作流运行编号，如 `8.0.0.57`。
- **许可证表达式**按 configure 参数确定（`LGPL-2.1-or-later`、`GPL-2.0-or-later`，带 `--enable-version3` 时为对应的 `-3.0` 版本）。

```text
build/native/<rid>/            每个平台的完整文件，与 zip 输出一致
                               （include/、lib/、bin/、share/、BUILDINFO.txt）
build/native/<id>.targets      C++（vcxproj）集成
runtimes/<rid>/native/         供 .NET 使用的可执行文件和共享库
lib/netstandard2.0/_._         让 .NET 项目可以安装此包
README.md                      包说明
```

RID：`linux-x64`、`linux-x86`、`linux-arm64`、`linux-arm`、`osx-x64`、`osx-arm64`、`win-x64`、`win-x86`、`win-arm64`（来自 `docs/targets.json`）。

NuGet 包不能包含符号链接，因此 Linux / macOS 的 `build/native/<rid>/lib/` 中以普通文件保存 `libavcodec.so` + `libavcodec.so.63`（`libavcodec.dylib` + `libavcodec.63.dylib`），省略没有被引用的完整版本号文件。

**C# / .NET**：在 SDK 风格项目中添加此包，`runtimes/<rid>/native/` 会自动复制到输出目录。通过 P/Invoke（或 FFmpeg.AutoGen）按带版本号的库名调用——Windows 为 `avutil-61.dll`，Linux 为 `libavutil.so.61`，macOS 为 `libavutil.61.dylib`：

```csharp
[DllImport("avutil-61")]
static extern IntPtr av_version_info();
```

在 Linux 和 macOS 上，包中的 `ffmpeg` / `ffprobe` 需要先 `chmod +x` 才能运行。

**C++（Visual C++，vcxproj）**：安装此包（packages.config）后，`build/native/<id>.targets` 会为 x64 / Win32 / ARM64 自动添加头文件目录、FFmpeg 头文件所需的 `__STDC_CONSTANT_MACROS` 宏、导入库（`avcodec.lib` 等），并把 DLL 复制到可执行文件旁边；可通过 `FFmpegRid` 属性手动指定 RID。其它构建系统可直接使用 `build/native/<rid>/include`、`lib` 和 `lib/pkgconfig`。

## 第三方库

参照官方预编译版本（如 BtbN 的 FFmpeg-Builds、evermeet.cx）的做法，下列库会针对每个目标平台从源码编译并静态链接，产物运行时不依赖这些库。每个库对应 `deps/NN-name.sh` 中的一个编译脚本，版本、下载地址和 SHA256 都已固定。

| 库 | 版本 | 许可证 | FFmpeg 参数 | 说明 |
|---|---|---|---|---|
| x264 | stable（2025-06） | GPL | `--enable-libx264` | H.264 编码器 |
| x265 | 4.1 | GPL | `--enable-libx265` | HEVC 编码器，8-bit |
| libvpx | 1.17.0 | BSD | `--enable-libvpx` | VP8 / VP9，支持高位深 |
| dav1d | 1.5.4 | BSD | `--enable-libdav1d` | AV1 解码器 |
| SVT-AV1 | 4.2.0 | BSD | `--enable-libsvtav1` | AV1 编码器，仅 64 位 |
| libaom | 3.15.2 | BSD | `--enable-libaom` | AV1 编解码器 |
| Opus | 1.5.2 | BSD | `--enable-libopus` | |
| LAME | 3.100 | LGPL | `--enable-libmp3lame` | MP3 编码器 |
| libogg / libvorbis | 1.3.6 / 1.3.7 | BSD | `--enable-libvorbis` | |
| libwebp | 1.6.0 | BSD | `--enable-libwebp` | |
| zimg | 3.0.6 | WTFPL | `--enable-libzimg` | zscale 滤镜 |
| SoX Resampler | 0.1.3 | LGPL | `--enable-libsoxr` | |
| libass + FreeType + HarfBuzz + FriBidi | 0.17.5 / 2.14.3 / 14.6.0 / 1.0.17 | ISC / FTL / MIT / LGPL | `--enable-libass --enable-libfreetype --enable-libharfbuzz --enable-libfribidi` | 字幕、drawtext |
| zlib | 1.3.2 | zlib | （自动检测） | |

- **许可证**：x264 和 x265 是 GPL，只有选择 GPL 许可证时才可用，此时产物也是 GPL；其余库可用于 LGPL 构建。
- **缓存**：每个目标平台第一次编译第三方库约需 20–40 分钟，结果保存在 Actions 缓存中，之后的编译直接复用。也可以先运行一次 **Actions → build-deps → Run workflow**，为所有平台预热缓存。修改某个库的脚本只会重新编译这个库。
- **添加新库**：新增 `deps/NN-name.sh`，写明 `DEP_VERSION`、`DEP_URL`、`DEP_SHA256`，并用 `scripts/build-deps.sh` 提供的 `autotools_build`、`cmake_build` 或 `meson_build` 实现 `dep_build`；再在 `docs/configure.js` 和 `docs/i18n.js` 中为它的 `--enable-lib...` 参数加一个开关。

## configure 参数说明

- 参数以空格或换行分隔，仅允许 `[-+./:=,@%A-Za-z0-9_]` 字符，含 `` ; & | $ > ` `` 或空格的值会被拒绝（因此 `--extra-cflags="-O3 -march=native"` 这类带空格的参数无法使用）。
- 工作流会在你的参数**之前**自动注入交叉编译参数和 `--cc=ccache ...`；如需覆盖，直接写同名参数即可（后出现者生效）。
- 不能指定 `--prefix`：安装路径由编译流程管理，工作流会拒绝该参数。
- 只有“第三方库”一节列出的库可用；其它 `--enable-lib...` 参数（如 `--enable-libfdk-aac`）会在 configure 阶段失败，除非为它添加编译脚本。

### 网页上的可视化参数

网页把常用的 configure 开关做成了可视化控件，按 **构建类型 / 链接方式 / 许可证 → 程序与库 → 功能特性 → 组件 → 自定义参数** 的顺序生成参数，并实时显示“最终 configure 参数”（可一键复制）。当前配置会保存在浏览器本地，下次打开自动恢复；“恢复默认”可重置。鼠标悬停在选项上可查看说明和对应参数。

| 分组 | 选项 | 对应参数 |
|---|---|---|
| 构建类型 | **Release**（默认）／RelWithDebInfo／Debug | `--disable-debug`／`--disable-stripping`／`--enable-debug=3 --disable-optimizations --disable-stripping` |
| 链接方式 | **静态**（默认）／共享／静态 + 共享 | `--enable-static --disable-shared`／`--enable-shared --disable-static`／两者都启用 |
| 许可证 | LGPL／**GPL**（默认） | 不加参数／`--enable-gpl` |
| 程序与库 | ffmpeg、ffprobe、libavdevice、libavfilter、libswscale、libswresample、文档 | 取消勾选即 `--disable-<名称>`（文档默认不生成：`--disable-doc`） |
| 功能特性 | 汇编优化、硬件加速、网络协议、自动探测系统库、体积优化、PIC | `--disable-asm`、`--disable-hwaccels`、`--disable-network`、`--disable-autodetect`、`--enable-small`、`--enable-pic` |
| 第三方库 | x264、x265、libvpx、dav1d、SVT-AV1、libaom、Opus、LAME、Vorbis、WebP、zimg、SoX 重采样、libass（默认全部开启） | `--enable-libx264` 等 |
| 组件 | **全部组件**（默认）／精简 | 精简模式：`--disable-everything` + 按类别勾选的 `--enable-decoder=...`、`--enable-demuxer=...` 等 |

- **组件精简**：可按解码器、编码器、解封装、封装、解析器、比特流滤镜、协议、滤镜分别勾选，每类都有“全选 / 清空 / 常用”快捷按钮。适合嵌入播放器、移动端等对体积敏感的场景。
- **无效组合直接不可选**：页面通过交互约束避免错误配置，而不是事后校验：
  - **依赖自动联动**：关闭 libavfilter 会同时关闭 ffmpeg（ffmpeg 依赖它），勾选 ffmpeg 会自动开启 libavfilter，页面会提示并高亮被联动的选项。
  - **许可证**：仅限 GPL 的组件（如 `hqdn3d`、`delogo`、`eq`、`cropdetect`、`mpdecimate` 滤镜）带 **GPL** 标记，选择 LGPL 时变灰不可选。
  - **库依赖**：关闭 libswscale / libswresample 后，精简模式中的 `scale` / `aresample` 滤镜变灰不可选。
  - **目标平台**：目标平台为 Linux 时 `https` 协议不可选（Linux 编译环境没有 TLS 库）。
  - **第三方库**：x264 / x265（GPL）在 LGPL 下不可选；SVT-AV1 仅支持 64 位，在 Linux / Windows x86、Linux armv7 下不可选（NuGet 勾选的指令集中包含它们时同样不可选）。
  - **精简模式**：`file` 协议固定保留，保证能读写本地文件。
  - 灰色选项悬停可查看原因；限制解除后（如切回 GPL），之前的勾选会自动恢复。
- **为什么没有 GPL v3**：FFmpeg 自带组件中没有任何一个要求 version3，它只影响 opencore-amr、mbedtls 等第三方库。编译环境没有这些库，因此只提供 LGPL / GPL；需要时可在自定义参数中写 `--enable-version3`。
- **Debug 构建**：FFmpeg 依赖编译器的死代码消除，不支持 `-O0`，因此 Debug 仍会保留最低限度的优化。
- **自定义参数**：在“高级 → 自定义参数”中自由输入，追加在最后并可覆盖上面的选项（同一开关以后出现的为准；`--enable-decoder=` 这类组件参数可以多次出现）。输入时会自动过滤 `[-+./:=,@%A-Za-z0-9_]` 以外的字符；参数本身不做校验，写错的参数会在 Actions 的 configure 阶段失败并在 Issue 中回复。

## 编译流程

1. 网页把参数编码进新建 Issue 的链接（`/issues/new?template=<当前语言的模板>&...`），由你在 GitHub 上确认提交。
2. `issues: opened` 事件触发工作流。**setup** 任务：
   - 只处理标题以 `[build]` 开头、且提交人为仓库 `OWNER` / `MEMBER` / `COLLABORATOR` 的 Issue，其余直接跳过；
   - 根据 Issue 表单的标题文字识别语言（英文 / 中文 / 日文），之后的所有回复都使用该语言；
   - `scripts/parse-issue.py` 解析 Issue 正文，`scripts/resolve-params.sh` 校验平台、指令集、打包格式、源码地址、ref 与 configure 参数，生成 release tag 和构建矩阵；
   - 校验失败时在 Issue 中回复错误原因并关闭；成功时打上 `build` 标签并回复“已开始编译”。
3. **build**（矩阵并行）：
   - `actions/checkout` 拉取源码（私有仓库使用 `SOURCE_PAT` Secret，`persist-credentials: false`）；
   - 安装编译工具（Linux x86_64 / arm64 在 manylinux_2_28 容器中编译，Linux x86 / armv7 在 Ubuntu 20.04 容器中交叉编译；Windows 在 Ubuntu 上用 llvm-mingw）；
   - 从 Actions 缓存恢复第三方库，缺少的由 `scripts/build-deps.sh` 补齐；
   - 恢复 ccache 缓存；
   - `scripts/build-ffmpeg.sh`：configure → make → make install → 修正 rpath / install name / `.pc` 路径 → 打包 Windows 运行时 DLL → `ffmpeg -version` 冒烟测试（armv7 通过 qemu-user 运行；Windows 跳过）→ 写入 `BUILDINFO.txt` → 打包；
   - 上传 Artifact。
4. **lipo**（仅 macOS universal）：合并两个架构的可执行文件、动态库与静态库。
5. **release**：汇总所有成功的产物（NuGet 格式时先由 `scripts/pack-nuget.py` 把各平台压缩包合并为一个 `.nupkg`），生成 `SHA256SUMS.txt`，一次性创建 Draft Release，然后在 Issue 中回复结果，成功则关闭 Issue。

## 安全设计

- **网页不处理任何令牌**：触发编译依靠你在 github.com 上的登录身份提交 Issue，网页只读取公开 API，不存在令牌被仿冒页面骗取或泄露的问题。
- **只执行可信用户的请求**：公开仓库任何人都能提交 Issue，工作流只处理仓库所有者、组织成员和协作者提交的编译 Issue。
- **私有源码令牌放在 Secret 中**：`SOURCE_PAT` 只在工作流内使用，日志自动打码，源码检出后不保留凭证。
- **输入严格校验**：Issue 内容视为不可信数据，全部通过环境变量传给脚本，从不直接拼接进 shell 命令；平台、指令集、格式只接受固定取值，configure 参数只允许安全字符集，源码地址只接受 `github.com` 仓库。
- 公开仓库的编译 Issue 对所有人可见（包括源码仓库地址和 configure 参数）。如不希望公开，可将 Fork 设为私有仓库，此时网页的“编译记录”无法读取，请直接在 GitHub 上查看 Issues。

## 已知限制

- **Linux x86 / armv7** 需要 glibc 2.31+（高于 64 位产物的 2.28）。armv7 以 armhf 基线（VFPv3-D16）为目标，不假定 NEON，因此 libaom 和 zimg 在该平台不使用 SIMD；FFmpeg 自身的 NEON 代码仍会在运行时按 CPU 选择。
- **Windows** 为交叉编译，不运行冒烟测试。
- **x265** 目前只编译 8-bit（暂不支持 10/12-bit 多位深）。
- **TLS**：Linux 构建没有 TLS 库，因此不支持 `https`；Windows 使用 Schannel，macOS 使用系统 TLS。
- **Linux 上的 libass** 未编译 fontconfig：字幕字体来自字幕文件内嵌的字体或滤镜的 `fontsdir` 参数。
- 每个目标平台第一次编译第三方库约需 20–40 分钟，缓存后不再重复。
- **macOS Intel**：GitHub 预计在 2027 年秋随 macOS 15 镜像退役而停止提供 Intel runner，届时 macOS x86_64 / universal 需改为在 arm64 上交叉编译。
- 页面需以 `https://<owner>.github.io/<repo>/` 形式访问才能自动识别仓库；绑定自定义域名后无法识别。
- 修改已提交 Issue 的内容不会重新触发编译，如需调整参数请提交新的 Issue。

## 可扩展方向

- 在 Pages 中配置并保存多套 configure 预设
- 更多第三方库（Linux 的 OpenSSL / TLS、fontconfig、x265 多位深等）

## 许可证

本仓库已附带 **MIT License**，支持任意个人或商用 Fork、自定义和再分发。
