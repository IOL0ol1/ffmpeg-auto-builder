# FFmpeg Auto Builder

[English](README.md) | 简体中文

基于 **GitHub Pages + GitHub Issues + GitHub Actions** 的 FFmpeg 在线编译模板仓库。Fork 后开启 Actions、Issues 和 Pages，在网页上选好参数即可生成一条预填的编译 Issue；提交该 Issue，工作流就开始编译，产物发布到 Draft Release。

## 核心功能

- **网页生成编译 Issue**：填写源码仓库、分支 / tag / commit、打包格式、目标平台、指令集和 configure 参数，一键生成预填好的 Issue，提交即触发编译。
- **状态全部回帖到 Issue**：开始、失败、完成都有评论，附 Draft Release 链接、运行详情链接和各目标结果表；成功后自动关闭 Issue。
- **只执行可信用户的请求**：仅处理由仓库 Owner / 组织成员 / 协作者提交的 `[build]` Issue，其他人提交的 Issue 不会消耗 Actions 额度。
- **多平台交叉编译**（见下表），Apple 平台可用 lipo 合并出 universal 二进制。
- **第三方库从源码编译并静态链接**：x264、x265、libvpx、dav1d、SVT-AV1、libaom、Opus、LAME、Vorbis、WebP、zimg、SoX 重采样、libass（含 FreeType / HarfBuzz / FriBidi）、zlib。版本固定，网页上可逐个开关，也可改为共享库随包分发。
- **五种打包格式**：`tar.gz`、`zip`、NuGet（C++ / C#）、Android AAR（带 Prefab）、Apple XCFramework；合并类格式可包含多个指令集。
- **产物开箱可用**：自动修正 rpath / install name，`.pc` 改为相对路径，Windows 静态构建不依赖额外 DLL；每个包都带 `lib/cmake/FFmpeg`（支持 `find_package(FFmpeg)`）、`BUILDINFO.txt`，Release 附 `SHA256SUMS.txt`。
- **构建加速**：ccache 增量编译；第三方库编译结果进 Actions 缓存，后续构建直接复用。
- 仓库名、用户名、密钥均未硬编码，Fork 后不改代码即可用。

## 目录结构

```text
deps/          第三方库编译脚本（版本、下载地址、SHA256、编译步骤）
docs/          GitHub Pages 前端 + targets.json（平台、指令集、runner、约束）
scripts/       参数解析与校验、构建、打包、lipo 合并
.github/       Issue 表单与 build-ffmpeg / build-deps 工作流
```

## 支持的目标

| 平台 | 指令集 | 说明 |
|---|---|---|
| linux | x86_64、arm64、x86、armv7、armel、ppc64le、s390x、riscv64、mips64el、mipsel、loongarch64 | x86_64 / arm64 原生编译（glibc 2.28+），其余交叉编译（glibc 2.31+，loongarch64 为 2.36+） |
| macos | x86_64、arm64、universal | 原生编译，macOS 11+ |
| windows | x86_64、x86、arm64 | llvm-mingw 交叉编译，Windows 10+ |
| android | arm64-v8a、armeabi-v7a、x86_64、x86 | NDK r27d，API 21+ |
| ios / tvos / visionos | arm64 + 各模拟器 | Xcode，只有静态库，不编译 ffmpeg / ffprobe 程序 |
| maccatalyst | arm64、x86_64、universal | Xcode，Mac Catalyst 14+ |
| freebsd | x86_64、arm64 | FreeBSD 14.4+ |
| wasm | wasm32 | Emscripten，单线程静态库 |

## 使用方法

### 1. Fork 并开启功能

1. Fork 本仓库到自己的账号（或可写组织）。
2. **Actions** 页点击启用工作流（Fork 默认禁用）。
3. **Settings → General → Features** 勾选 **Issues**（Fork 默认关闭）。
4. **Settings → Pages**：Source 选 `Deploy from a branch`，分支选默认分支，Folder 选 `/docs`。
5. 一两分钟后得到 `https://<owner>.github.io/<repo>/`，之后也可从仓库 **Deployments → github-pages** 进入。

### 2. 私有源码仓库（可选）

源码是公开仓库时跳过。私有仓库需要一个 Fine-grained PAT（只给 `Contents: Read-only`），在 Fork 仓库 **Settings → Secrets and variables → Actions** 中保存为 `SOURCE_PAT`。未配置时工作流只带 `GITHUB_TOKEN`，无法读取私有仓库。

### 3. 在网页上填表并提交

| 字段 | 说明 |
|---|---|
| FFmpeg Git 仓库地址 | GitHub 仓库，HTTPS 或 SSH 写法 |
| 分支 / tag / commit | 可选；commit 需 40 位完整 SHA |
| 打包格式 | `tar.gz` / `zip` / NuGet / AAR / XCFramework |
| 目标平台、指令集 | 选项随平台和格式变化 |
| 编译参数 | 可视化选择构建类型、链接方式、许可证、程序与库、特性、组件，也可追加自定义参数，实时显示最终 configure 参数 |

点击提交后到 GitHub 确认并 **Submit new issue**，几秒内工作流开始在 Issue 中回帖。也可以不用网页，直接在 **Issues → New issue** 里选编译模板填写。

### 4. 获取与使用产物

产物在 **Draft Release** 中（仅所有者 / 协作者可见，确认后点 **Publish release** 公开），也可在运行页底部下载 Artifact（需登录，默认保留 90 天）。

压缩包名为 `ffmpeg-<平台>-<指令集>-<许可证>-<编译编号>.zip`，解压后：

```text
bin/            ffmpeg、ffprobe（Windows 还含 DLL）
lib/            静态库 / 共享库、pkgconfig/*.pc
include/        头文件
share/          示例与 man 页（视 configure 参数而定）
BUILDINFO.txt   源码仓库、ref、commit、编译器、configure 参数
```

- **直接运行**：`./bin/ffmpeg -version`，共享库构建已设好 rpath，不需要 `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`。
- **macOS 首次运行被拦截**：`xattr -dr com.apple.quarantine <解压目录>`。
- **作为开发库**：`export PKG_CONFIG_PATH=<解压目录>/lib/pkgconfig`。
- **CMake**：`-DCMAKE_PREFIX_PATH=<解压目录>` 后 `find_package(FFmpeg REQUIRED COMPONENTS avformat)`，得到 `FFmpeg::avcodec`、`FFmpeg::avformat` 等目标；需要静态库时设 `FFmpeg_USE_STATIC_LIBS=ON`。
- **Windows**：静态构建就是两个 exe，只依赖系统 DLL；静态库（`libavcodec.a` 等）由 MinGW 工具链生成，MSVC 项目请用共享库构建。

其他格式的接入方式：

- **NuGet**：包 ID 为 `<owner>.FFmpeg.<许可证>.<RID 或平台>`；C# 直接 `PackageReference`（`runtimes/<rid>/native/` 自动复制到输出），C++ 用包内 `build/native/<id>.targets`（vcxproj）。
- **AAR**：`implementation(files("libs/ffmpeg-....aar"))` 后用 `System.loadLibrary("avcodec")`；NDK 项目打开 Prefab 后 `find_package(ffmpeg)` 并链接 `ffmpeg::avformat`。
- **XCFramework**：SPM 中作为 `binaryTarget`，CocoaPods 中作为 `vendored_frameworks`；静态切片直接链接 `.a`，共享切片需 Embed & Sign。

### 备用：手动触发

**Actions → build-ffmpeg → Run workflow**，填同样的参数即可。结果只出现在运行页和 Releases 中，没有 Issue 评论。

## 注意事项

- **configure 参数只能用安全字符**：仅允许 `[-+./:=,@%A-Za-z0-9_]`，含空格或 ``; & | $ > ` `` 的参数会被拒绝，所以 `--extra-cflags="-O3 -march=native"` 这类写法不可用；`--prefix` 会被拒绝。参数本身不做校验，写错会在 configure 阶段失败并在 Issue 中回帖。
- **只能用内置的第三方库**：没写进 `deps/` 的 `--enable-lib...`（如 `--enable-libfdk-aac`）会在 configure 阶段失败；要加库需新增 `deps/NN-name.sh`（版本、URL、SHA256、`dep_build`）。
- **自定义参数追加在最后**，同名的后者生效；工作流会在你的参数之前注入交叉编译参数和 `--cc=ccache`。
- **GPL 限制**：x264 / x265 是 GPL，只有选 GPL 时才可用；LGPL 下相关的 GPL 组件在网页上直接置灰。
- **没有 GPLv3 选项**：内置组件都不需要 version3，需要时自己加 `--enable-version3`。
- **精简组件模式**：`--disable-everything` 加按类勾选的解码器 / 编码器 / 封装等；`file` 协议固定保留。
- **运行库基线**：Linux glibc 2.28+（非 x86_64 / arm64 为 2.31+）、macOS 11+、Windows 10+、Android API 21+、iOS / tvOS 13+、visionOS 1+。
- **冒烟测试只在 Linux（含 qemu-user）和 macOS 跑**；Windows、Android、Apple 移动端、FreeBSD、WASM 是交叉编译，无法在编译机上运行。
- **部分平台没有 TLS**：Linux、Android、visionOS、Mac Catalyst、FreeBSD、WASM 的构建不带 TLS 库，`https` 协议不可用；Windows 走 Schannel，Apple 平台走系统 TLS。
- **x265 只有 8-bit**；**Linux 上的 libass 没有 fontconfig**，字体需靠字幕内嵌或滤镜的 `fontsdir`。
- **iOS / tvOS / visionOS / WASM 只有静态库**，也没有 ffmpeg / ffprobe 程序；需要 framework 时用 XCFramework 格式。
- **NuGet**：固定共享库；指令集是多选，多个指令集打进同一个包，不提供 universal；只支持静态库的平台不能打成 NuGet。
- **AAR**：固定共享库，不含 ffmpeg / ffprobe 程序。
- **XCFramework**：不能同时包含静态和共享，一个 XCFramework 只有一种形式。
- **首次编译第三方库需 20–40 分钟**，之后走缓存；只想预热可先跑一次 `build-deps` 工作流。改某个库的脚本只会重编该库。
- **改已提交的 Issue 不会重新编译**，参数要改就重新提交 Issue；校验失败时工作流会回帖原因并关闭该 Issue。
- 网页的编译记录走未登录 GitHub API，**每小时 60 次请求**，超限稍后再刷新。
- 公开仓库里的编译 Issue 对所有人可见（含源码地址和 configure 参数）。
- 网页必须通过 `https://<owner>.github.io/<repo>/` 打开才能识别仓库，绑定自定义域名后失效。
- GitHub 计划在 2027 年秋随 macOS 15 镜像退役停供 Intel runner，届时 macOS x86_64 / universal 需改为在 arm64 上交叉编译。

## 许可证

MIT License。
