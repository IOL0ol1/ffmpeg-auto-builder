# FFmpeg Auto Builder

English | [简体中文](README.zh-CN.md)

A template repository for building FFmpeg online with **GitHub Pages + GitHub Issues + GitHub Actions**. Fork it, enable Actions, Issues and Pages, and you get a visual FFmpeg build tool that runs entirely on GitHub — no third-party backend, and **no token is ever entered on the web page**.

**[Open the web page →](../../deployments/github-pages)** (in any fork this opens that fork's own Pages deployment; click **View deployment** there, or use **Deployments** in the sidebar.)

## Features

- Fill in the source repository, branch/tag/commit, package format, target platform, architecture and configure options on the web page, and it generates a prefilled build issue.
- Submitting the issue on GitHub starts the build. Your GitHub sign-in is the only credential; the page never touches a token.
- Only build issues opened by the repository owner or collaborators are run, so other people's issues cannot spend your Actions minutes.
- The workflow comments on the issue when the build starts, fails or finishes, with links to the draft release and artifacts; GitHub notifies you according to your notification settings.
- Builds public FFmpeg repositories, and private FFmpeg forks once a `SOURCE_PAT` secret is configured.
- Linux (x86_64, x86, arm64, armv7, armel, ppc64le, s390x, riscv64, mips64el, mipsel, loongarch64), macOS, Windows, Android, iOS, tvOS, visionOS, Mac Catalyst, FreeBSD and WebAssembly; Apple targets can produce universal (fat) binaries.
- Like the official prebuilt FFmpeg binaries, common **third-party libraries are built from source and linked statically** (x264, x265, libvpx, dav1d, SVT-AV1, libaom, Opus, LAME, Vorbis, WebP, zimg, SoX resampler, libass); each one can be toggled on the page.
- Linux x86_64 / arm64 builds run on glibc 2.28+ (RHEL 8, Debian 10, Ubuntu 20.04 and newer), the other Linux architectures on glibc 2.31+ (loongarch64: 2.36+); Windows is cross-compiled with llvm-mingw into self-contained executables; macOS supports 11.0+. See "Platforms and architectures".
- ccache for incremental builds, a smoke test, and a single draft release per build (with `SHA256SUMS.txt`).
- Packages as `tar.gz`, `zip` or a **NuGet package** for C++ and C# projects; one NuGet package can contain any selection of the platform's architectures.
- Packages work right after extraction: shared builds get fixed rpaths / install names, `.pc` files use relative paths, Windows executables need no extra DLLs, and every package contains `BUILDINFO.txt`.
- The page lists recent builds, their status and a job/step log summary.
- The page can be switched between **English / 简体中文 / 日本語** (defaults to the browser language); the generated issue and the workflow's replies use the same language.
- No repository names, user names or secrets are hard-coded, so a fork works without code changes.

## Repository layout

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/           # Build request issue forms (build.yml English / build-zh-CN.yml / build-ja.yml)
│   └── workflows/
│       ├── build.yml             # Build pipeline (setup → build matrix → lipo → release)
│       └── deps.yml              # Builds and caches the third-party libraries ahead of time
├── deps/                         # One recipe per third-party library (version, URL, SHA256, build steps)
├── docs/                         # GitHub Pages site (index.html / app.js / configure.js / i18n.js / styles.css)
│   └── targets.json              # Build targets: platforms, architectures, runners, constraints
└── scripts/
    ├── common.sh                 # Shared helpers (repository URL parsing, flag filtering, ...)
    ├── parse-issue.py            # Parses build parameters from an issue body and detects its language
    ├── issue-comment.sh          # Posts the started / invalid / result replies in the issue's language
    ├── resolve-params.sh         # Validates parameters, creates the release tag and build matrix
    ├── targets.py                # Reads docs/targets.json: validation, build matrices
    ├── install-deps.sh           # Installs build tools (platform_install)
    ├── toolchain.sh              # Toolchain setup shared by the library and FFmpeg builds (platform_toolchain)
    ├── platforms/<platform>.sh   # Per-platform build tools and toolchain
    ├── build-deps.sh             # Builds deps/*.sh into a static library prefix
    ├── build-ffmpeg.sh           # Builds, fixes install paths, runs the smoke test and packages
    ├── pack-nuget.py             # Combines the architecture archives into one NuGet package
    └── merge-slices.sh           # Merges single-architecture packages into a universal binary with lipo
```

## Getting started

### Step 1: Fork and enable features

1. Click **Fork** to copy this repository to your account (or an organization you can write to).
2. **Enable Actions**: open the fork's **Actions** tab and click **I understand my workflows, go ahead and enable them** (Actions are disabled on forks by default).
3. **Enable Issues**: open **Settings → General → Features** and check **Issues** (Issues are disabled on forks by default).
4. **Enable Pages**: open **Settings → Pages** and under **Build and deployment** choose:
   - **Source**: `Deploy from a branch`
   - **Branch**: the default branch, **Folder**: `/docs`
5. After a minute or two the Pages URL appears at the top, e.g. `https://<your-user>.github.io/<repo>/`. Leave **Custom domain** empty. Later you can also reach it from **Deployments → github-pages** in the repository sidebar or the "Open the web page" link at the top of this README; checking **Use your GitHub Pages website** under the gear icon next to **About** shows the URL on the repository home page.

### Step 2 (optional): Access token for private source repositories

Skip this step if the FFmpeg source repository is **public** (for example the official `https://github.com/FFmpeg/FFmpeg`).

For a **private** repository:

1. Create a fine-grained PAT at https://github.com/settings/personal-access-tokens/new:
   - **Repository access**: **Only select repositories**, and select the private FFmpeg repositories to build (several are fine);
   - **Repository permissions**: only `Contents: Read-only`.
2. Open the fork's **Settings → Secrets and variables → Actions → New repository secret**.
3. Set **Name** to `SOURCE_PAT`, paste the token as the **Secret**, and save.

The workflow reads it as a secret (masked in logs). Without it, the workflow's own `GITHUB_TOKEN` is used, which can only read public repositories — a private repository under the same account still needs `SOURCE_PAT`.

### Step 3: Fill in the form on the page

Open the Pages URL from step 1. The top shows the detected repository and whether Issues are enabled; the language menu in the top-right corner switches between English / 简体中文 / 日本語, and the submitted issue and the workflow's replies follow that language.

| Field | Description | Example |
|---|---|---|
| FFmpeg Git repository | A GitHub repository, HTTPS or SSH form | `https://github.com/FFmpeg/FFmpeg` |
| Branch / tag / commit | Optional; commits need the full 40-character SHA | `n7.1`, `release/7.1` |
| Package format | `tar.gz`, `zip` or `NuGet (.nupkg)` (see "NuGet package") | `zip` |
| Target platform | `Linux` / `macOS` / `Windows` | `Linux` |
| Target architecture | Depends on the platform and package format; see the table below | `x86_64` |
| Build options | Visual controls for build type, linking, license, programs & libraries, features and components, plus optional custom flags; the final configure flags are shown live (see "configure options") | Release + static + GPL |

Click **Submit on GitHub**. The page checks the inputs, then opens GitHub's new-issue page in a new tab with everything filled in.

### Step 4: Submit the issue on GitHub

1. Make sure you are signed in as the repository owner (or a collaborator) and review the parameters.
2. Click **Submit new issue**.
3. Within seconds the workflow starts and replies **🚀 Build started** with a parameter table and a link to the run.

> You can also skip the page: open **Issues → New issue**, pick the **FFmpeg Build** / **FFmpeg 编译** / **FFmpeg ビルド** template and fill it in. The workflow replies in the template's language.

### Step 5: Follow progress and download

- **Issue comment**: when the build ends you get **✅ Build finished**, **⚠️ Some targets failed** or **❌ Build failed**, containing:
  - a link to the **draft release** (all packages plus `SHA256SUMS.txt`). Drafts are visible only to the owner and collaborators; click **Publish release** on the release page to make it public;
  - a link to the **run details**, where the artifacts can be downloaded at the bottom (requires signing in to GitHub; kept for 90 days by default);
  - a result table for each platform job.
- The issue is closed automatically after a successful build and stays open after a failure.
- **"Builds" on the page**: lists the latest 20 build issues with their status, and can expand a job/step log summary. It refreshes every 10 minutes while a build is running, or on demand with **Refresh**. The page calls the GitHub API without signing in, which is limited to 60 requests per hour; wait a bit if you hit the limit.
- If parameters are invalid (e.g. a wrong platform or disallowed characters in the configure flags), the workflow replies with the reason and closes the issue; fix it and submit a new issue.

### Step 6: Use the package

Archives are named `ffmpeg-<platform>-<arch>-<license>-<build id>.zip` (or `.tar.gz`), where the license is `gpl`, `lgpl`, `gplv3`, `lgplv3` or `nonfree` as given by the configure flags, e.g. `ffmpeg-linux-x86_64-gpl-20261016t080000-i42.tar.gz`. Layout after extraction:

```text
bin/            ffmpeg, ffprobe (and DLLs on Windows)
lib/            static / shared libraries, pkgconfig/*.pc
                (static builds also contain the third-party static libraries, libx264.a, ...)
                (Windows shared builds: import libraries avcodec.lib, ... plus .def files)
include/        headers
share/          examples and man pages (depending on configure options)
BUILDINFO.txt   source repository, ref, commit, compiler, configure flags
```

- **Run directly**: `./bin/ffmpeg -version`. Shared builds have their rpath set (`$ORIGIN/../lib` on Linux, `@loader_path/../lib` on macOS), so no `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` is needed.
- **macOS**: if the first run is blocked because the developer cannot be verified, run `xattr -dr com.apple.quarantine <extracted-dir>`.
- **As a development library**: `export PKG_CONFIG_PATH=<extracted-dir>/lib/pkgconfig`; the `.pc` files use relative paths, so the directory can live anywhere.
- **Windows**: static builds are single `ffmpeg.exe` / `ffprobe.exe` files that only depend on Windows system DLLs (Windows 10+). Shared builds put `avcodec-63.dll` and friends in `bin/` and the import libraries `avcodec.lib` etc. in `lib/`, which MSVC, clang-cl and MinGW can all link against. The static libraries of a static build (`libavcodec.a` etc.) come from the MinGW toolchain and need it (or clang) to link; use a shared build from MSVC.
- **Library names**: Linux `libavcodec.so` → `libavcodec.so.63` → `libavcodec.so.63.x.y` (symlinks, SONAME `libavcodec.so.63`); macOS `libavcodec.dylib` → `libavcodec.63.dylib` → `libavcodec.63.x.y.dylib` (install name `@rpath/libavcodec.63.dylib`).

### Alternative: run the workflow manually

Open **Actions → build-ffmpeg → Run workflow** and fill in the same parameters. Results then appear only on the Actions run page and under Releases; there are no issue comments.

## Platforms and architectures

Every target is defined in `docs/targets.json` (runner, container, NuGet RID and what it can build); the page, the workflow and the NuGet packer read it from there.

| Platform | Architectures | Built on | Notes |
|---|---|---|---|
| linux | x86_64, arm64 | ubuntu-latest / ubuntu-24.04-arm, manylinux_2_28 container | Native, glibc 2.28+ |
| linux | x86, armv7, armel, ppc64le, s390x, riscv64, mips64el, mipsel | ubuntu-latest, Ubuntu 20.04 container | Cross-compiled with the distribution's GCC, glibc 2.31+; smoke test through qemu-user |
| linux | loongarch64 | ubuntu-latest, Ubuntu 24.04 container | Loongson's cross toolchain (GCC 14), glibc 2.36+ (new-world ABI) |
| macos | x86_64, arm64, universal | macos-15-intel / macos-15 | Native, macOS 11+; universal = lipo of both |
| windows | x86_64, x86, arm64 | ubuntu-latest | llvm-mingw cross-compile, Windows 10+ |
| android | arm64 (arm64-v8a), armv7 (armeabi-v7a), x86_64, x86 | ubuntu-latest | Android NDK r27d, API 21+, static libc++ |
| ios | arm64 (device), sim_arm64, sim_x86_64, sim_universal | macos-15 | Xcode, iOS 13+; static libraries only, no ffmpeg / ffprobe programs |
| tvos | arm64 (device), sim_arm64, sim_x86_64, sim_universal | macos-15 | Xcode, tvOS 13+; static libraries only, no programs |
| visionos | arm64 (device), sim_arm64 | macos-15 | Xcode, visionOS 1+; static libraries only, no programs |
| maccatalyst | arm64, x86_64, universal | macos-15 | Xcode, Mac Catalyst 14+ (iOS apps on macOS) |
| freebsd | x86_64, arm64 | ubuntu-latest | clang + lld against the FreeBSD 14.4 base system; runs on 14.4+ and 15.x |
| wasm | wasm32 | ubuntu-latest | Emscripten 6.0.10; static, single-threaded libraries for Emscripten projects |

> - `universal` / `sim_universal` (`tar.gz` / `zip`) merge the two architectures into fat binaries with lipo.
> - With NuGet, the architecture becomes a multi-select: every checked architecture is built in parallel and packed into one NuGet package (merged architectures are not offered there; check the single ones instead). Platforms that only build static libraries (iOS, tvOS, visionOS, WebAssembly) cannot be packaged as NuGet.
> - The smoke test (`ffmpeg -version`) runs on Linux (natively or through qemu-user) and macOS; the other targets cannot run on the build host.
> - If some architectures fail, the successful packages are still published to the draft release.

## NuGet package

With **Package format = NuGet**, the release contains one `.nupkg` instead of archives. Check the architectures to include; they all go into the same package. NuGet packages always use **shared linking** (the page locks the linking option, and the workflow appends `--enable-shared --disable-static`).

- **Package ID**: `<repository owner>.FFmpeg.<license>.<platform>`. The license is `GPL`, `LGPL`, `GPLv3`, `LGPLv3` or `NonFree`; the platform is the RID for a single architecture (`win-x64`, `linux-arm`, …) and the platform name (`win` / `linux` / `osx`) for several architectures. For example `IOL0ol1.FFmpeg.LGPL.win-x64` or `IOL0ol1.FFmpeg.GPL.linux`. **Version**: the FFmpeg version from the source's `RELEASE` file plus the workflow run number, e.g. `8.0.0.57`.
- **License expression** follows the configure flags (`LGPL-2.1-or-later`, `GPL-2.0-or-later`, or the `-3.0` variants with `--enable-version3`).

```text
build/native/<rid>/            complete files per platform, same as the zip output
                               (include/, lib/, bin/, share/, BUILDINFO.txt)
build/native/<id>.targets      C++ (vcxproj) integration
runtimes/<rid>/native/         executables and shared libraries for .NET
lib/netstandard2.0/_._         marks the package as compatible with .NET projects
README.md                      package readme
```

RIDs: `linux-x64`, `linux-x86`, `linux-arm64`, `linux-arm`, `osx-x64`, `osx-arm64`, `win-x64`, `win-x86`, `win-arm64` (from `docs/targets.json`).

NuGet packages cannot contain symlinks, so on Linux / macOS `build/native/<rid>/lib/` holds `libavcodec.so` + `libavcodec.so.63` (`libavcodec.dylib` + `libavcodec.63.dylib`) as regular files and leaves out the full-version name, which nothing refers to.

**C# / .NET**: add the package to an SDK-style project; `runtimes/<rid>/native/` is copied to the output automatically. Call FFmpeg with P/Invoke (or FFmpeg.AutoGen) using the versioned library names — `avutil-61.dll` on Windows, `libavutil.so.61` on Linux, `libavutil.61.dylib` on macOS:

```csharp
[DllImport("avutil-61")]
static extern IntPtr av_version_info();
```

On Linux and macOS, `ffmpeg` / `ffprobe` from the package need `chmod +x` before they can be run.

**C++ (Visual C++, vcxproj)**: install the package (packages.config) and `build/native/<id>.targets` adds, for x64 / Win32 / ARM64, the include directory, the `__STDC_CONSTANT_MACROS` define required by FFmpeg headers, the import libraries (`avcodec.lib`, …) and copies the DLLs next to the executable. Set the `FFmpegRid` property to choose a RID manually. Other build systems can use `build/native/<rid>/include`, `lib` and `lib/pkgconfig` directly.

## Third-party libraries

Following the approach of the official prebuilt binaries (for example BtbN's FFmpeg-Builds and evermeet.cx), the libraries below are built from source for every target and linked statically, so the packages do not depend on any of them at run time. Each library is a recipe in `deps/NN-name.sh` with a pinned version, download URL and SHA256.

| Library | Version | License | FFmpeg flag | Notes |
|---|---|---|---|---|
| x264 | stable (2025-06) | GPL | `--enable-libx264` | H.264 encoder |
| x265 | 4.1 | GPL | `--enable-libx265` | HEVC encoder, 8-bit |
| libvpx | 1.17.0 | BSD | `--enable-libvpx` | VP8 / VP9, high bit depth |
| dav1d | 1.5.4 | BSD | `--enable-libdav1d` | AV1 decoder |
| SVT-AV1 | 4.2.0 | BSD | `--enable-libsvtav1` | AV1 encoder, 64-bit only |
| libaom | 3.15.2 | BSD | `--enable-libaom` | AV1 encoder / decoder |
| Opus | 1.5.2 | BSD | `--enable-libopus` | |
| LAME | 3.100 | LGPL | `--enable-libmp3lame` | MP3 encoder |
| libogg / libvorbis | 1.3.6 / 1.3.7 | BSD | `--enable-libvorbis` | |
| libwebp | 1.6.0 | BSD | `--enable-libwebp` | |
| zimg | 3.0.6 | WTFPL | `--enable-libzimg` | zscale filter |
| SoX Resampler | 0.1.3 | LGPL | `--enable-libsoxr` | |
| libass + FreeType + HarfBuzz + FriBidi | 0.17.5 / 2.14.3 / 14.6.0 / 1.0.17 | ISC / FTL / MIT / LGPL | `--enable-libass --enable-libfreetype --enable-libharfbuzz --enable-libfribidi` | subtitles, drawtext |
| zlib | 1.3.2 | zlib | (autodetected) | |

- **Licensing**: x264 and x265 are GPL; they are only available with the GPL license selected, and the resulting binaries are then GPL. The other libraries are compatible with LGPL builds.
- **Caching**: the first build of the libraries for a target takes 20–40 minutes; the result is stored in the Actions cache and later builds reuse it. Running **Actions → build-deps → Run workflow** once warms the cache for all targets. Changing a recipe rebuilds only that library.
- **Adding a library**: add `deps/NN-name.sh` with `DEP_VERSION`, `DEP_URL`, `DEP_SHA256` and a `dep_build` function using the `autotools_build`, `cmake_build` or `meson_build` helpers from `scripts/build-deps.sh`, then add a toggle for its `--enable-lib...` flag in `docs/configure.js` and `docs/i18n.js`.

## configure options

- Flags are separated by spaces or new lines and may only contain `[-+./:=,@%A-Za-z0-9_]`; values with `` ; & | $ > ` `` or spaces are rejected (so flags such as `--extra-cflags="-O3 -march=native"` cannot be used).
- The workflow injects cross-compilation flags and `--cc=ccache ...` **before** your flags; to override them, pass the same flag yourself (the later one wins).
- `--prefix` cannot be set: the install path is managed by the build, and the workflow rejects it.
- Only the libraries listed under "Third-party libraries" are available; other `--enable-lib...` flags (for example `--enable-libfdk-aac`) fail at the configure step unless you add a recipe for them.

### Visual options on the page

The page turns common configure switches into visual controls and builds the flags in the order **build type / linking / license → programs & libraries → features → components → custom flags**, showing the final configure flags live (with a copy button). The current choices are saved in the browser and restored next time; **Reset** restores the defaults. Hover over an option to see its description and flags.

| Group | Options | Flags |
|---|---|---|
| Build type | **Release** (default) / RelWithDebInfo / Debug | `--disable-debug` / `--disable-stripping` / `--enable-debug=3 --disable-optimizations --disable-stripping` |
| Linking | **Static** (default) / Shared / Static + shared | `--enable-static --disable-shared` / `--enable-shared --disable-static` / both enabled |
| License | LGPL / **GPL** (default) | no flag / `--enable-gpl` |
| Programs & libraries | ffmpeg, ffprobe, libavdevice, libavfilter, libswscale, libswresample, docs | unchecking emits `--disable-<name>` (docs are off by default: `--disable-doc`) |
| Features | Assembly optimizations, hardware acceleration, network protocols, system library auto-detection, size optimization, PIC | `--disable-asm`, `--disable-hwaccels`, `--disable-network`, `--disable-autodetect`, `--enable-small`, `--enable-pic` |
| Third-party libraries | x264, x265, libvpx, dav1d, SVT-AV1, libaom, Opus, LAME, Vorbis, WebP, zimg, SoX resampler, libass (all on by default) | `--enable-libx264` and so on |
| Components | **All components** (default) / Slim | slim: `--disable-everything` plus the checked `--enable-decoder=...`, `--enable-demuxer=...` and so on |

- **Slim components**: pick decoders, encoders, demuxers, muxers, parsers, bitstream filters, protocols and filters per category, each with **Select all / Clear / Common** shortcuts. Useful for embedded players, mobile apps and other size-sensitive uses.
- **Invalid combinations cannot be selected**: the page prevents bad configurations through the controls rather than validating afterwards:
  - **Linked dependencies**: disabling libavfilter also disables ffmpeg (which depends on it), and enabling ffmpeg enables libavfilter; the page shows a notice and highlights the linked option.
  - **License**: GPL-only components (such as the `hqdn3d`, `delogo`, `eq`, `cropdetect` and `mpdecimate` filters) carry a **GPL** badge and are greyed out under LGPL.
  - **Library dependencies**: with libswscale / libswresample disabled, the `scale` / `aresample` filters are greyed out in slim mode.
  - **Target platform**: the `https` protocol is only available where the system provides TLS (macOS, Windows, iOS, tvOS). iOS / tvOS / visionOS / WebAssembly only offer static linking and no ffmpeg / ffprobe programs, and cannot be selected for NuGet.
  - **Third-party libraries**: x264 / x265 (GPL) are unavailable under LGPL, SVT-AV1 is only available on 64-bit x86 / Arm targets, and WebAssembly (single-threaded) has no x265, SVT-AV1, dav1d or libass; with several NuGet architectures a library must be available on all of them.
  - **Slim mode**: the `file` protocol is always kept so local files can be read and written.
  - Hover over a greyed-out option to see why; when the restriction is lifted (e.g. switching back to GPL), the earlier selection comes back.
- **Why there is no GPL v3**: no built-in FFmpeg component requires version3; it only affects third-party libraries such as opencore-amr and mbedtls. The build environment has none of them, so only LGPL / GPL are offered; add `--enable-version3` as a custom flag if needed.
- **Debug builds**: FFmpeg relies on the compiler's dead-code elimination and cannot be built at `-O0`, so Debug keeps a minimal level of optimization.
- **Custom flags**: free text under **Advanced → custom flags**, appended last so they can override any option above (for the same switch the later flag wins; component flags such as `--enable-decoder=` may appear several times). Characters outside `[-+./:=,@%A-Za-z0-9_]` are removed as you type; the flags themselves are not validated, and a wrong flag fails at the configure step on Actions and is reported on the issue.

## Build flow

1. The page encodes the parameters into a new-issue link (`/issues/new?template=<template for the current language>&...`), which you submit on GitHub.
2. The `issues: opened` event starts the workflow. The **setup** job:
   - only handles issues whose title starts with `[build]` and whose author is the repository `OWNER` / `MEMBER` / `COLLABORATOR`, and skips everything else;
   - detects the language (English / Chinese / Japanese) from the issue form's field labels; all replies use that language;
   - parses the issue body with `scripts/parse-issue.py`, and `scripts/resolve-params.sh` validates the platform, architecture, package format, source URL, ref and configure flags, then creates the release tag and build matrix;
   - on invalid parameters, replies with the reason and closes the issue; otherwise adds the `build` label and replies "Build started".
3. **build** (parallel matrix):
   - checks out the source with `actions/checkout` (private repositories use the `SOURCE_PAT` secret, with `persist-credentials: false`);
   - installs the build tools of the target (`scripts/platforms/<toolchain>.sh`; runner and container come from `docs/targets.json`);
   - restores the third-party library prefix from the Actions cache and builds whatever is missing with `scripts/build-deps.sh`;
   - restores the ccache cache;
   - `scripts/build-ffmpeg.sh`: configure → make → make install → fix rpath / install names / `.pc` paths → bundle Windows runtime DLLs → `ffmpeg -version` smoke test (other Linux architectures through qemu-user; skipped where the build host cannot run the result) → write `BUILDINFO.txt` → package;
   - uploads the artifact.
4. **lipo** (macOS universal only): merges executables, shared libraries and static libraries of both architectures.
5. **release**: collects every successful package (for NuGet, `scripts/pack-nuget.py` first combines the platform archives into one `.nupkg`), generates `SHA256SUMS.txt`, creates one draft release, then replies on the issue and closes it on success.

## Security

- **The page handles no tokens**: builds are triggered by issues you submit while signed in to github.com, and the page only reads public APIs, so no token can be phished or leaked through it.
- **Only trusted users' requests run**: anyone can open issues on a public repository, but the workflow only handles build issues from the owner, organization members and collaborators.
- **The private-source token lives in a secret**: `SOURCE_PAT` is only used inside the workflow, masked in logs, and no credentials are kept after checkout.
- **Strict input handling**: issue content is treated as untrusted, passed to scripts only through environment variables and never interpolated into shell commands; platform, architecture and format accept fixed values only, configure flags are limited to a safe character set, and source URLs must be `github.com` repositories.
- Build issues in a public repository are visible to everyone (including the source repository URL and configure flags). If that is not acceptable, make your fork private — the page's "Builds" list then cannot read it, so check Issues on GitHub instead.

## Known limitations

- **Linux cross-compiled architectures** need glibc 2.31+ (newer than the 2.28 of x86_64 / arm64; loongarch64 2.36+). They target the distribution baselines: armv7 is armhf (VFPv3-D16, NEON not assumed), armel is ARMv5TE soft-float, MIPS is MIPS32r2 / MIPS64r2 without DSP / MSA / Loongson extensions. Several libraries use portable C there (libaom, libvpx, zimg; x264 on armel / s390x / riscv64 / MIPS), so encoding is slower than on x86_64 / arm64.
- **Smoke test**: Windows, Android, the Apple mobile targets, FreeBSD and WebAssembly are cross-compiled and cannot run on the build host, so `ffmpeg -version` is not run for them.
- **Apple mobile / WebAssembly** packages contain static libraries only (FFmpeg's plus the third-party ones in `lib/`); link them into your app. There is no `.xcframework` packaging yet.
- **x265** is built 8-bit only (no 10/12-bit multilib yet).
- **TLS**: Linux, Android, visionOS, Mac Catalyst, FreeBSD and WebAssembly builds have no TLS library, so `https` is not available there; Windows uses Schannel and the Apple platforms the system TLS.
- **libass on Linux** is built without fontconfig: subtitle fonts come from the subtitle file's attachments or the filter's `fontsdir`.
- The first build of the third-party libraries for a target takes 20–40 minutes until it is cached.
- **macOS Intel**: GitHub plans to stop providing Intel runners when the macOS 15 image is retired in fall 2027; macOS x86_64 / universal will then need cross-compiling on arm64.
- The page must be opened as `https://<owner>.github.io/<repo>/` to detect the repository; it cannot with a custom domain.
- Editing a submitted issue does not start a new build; submit a new issue to change parameters.

## Ideas for extension

- Save several configure presets on the page
- More third-party libraries (OpenSSL / TLS for Linux, fontconfig, x265 multilib, ...)

## License

This repository is released under the **MIT License**, so it can be forked, customized and redistributed for personal or commercial use.
