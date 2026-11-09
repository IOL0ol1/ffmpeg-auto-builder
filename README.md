# FFmpeg Auto Builder

English | [简体中文](README.zh-CN.md)

A template repository that builds FFmpeg with **GitHub Pages + GitHub Issues + GitHub Actions**. Fork it, enable Actions, Issues and Pages, fill in the form on the page, and submit the prefilled build issue — the workflow builds it and publishes the packages to a draft release.

## What it does

- **The page generates a build issue**: pick the source repository, branch / tag / commit, package format, target platform, architecture and configure options; the page produces a prefilled issue, and submitting it starts the build.
- **Status is reported back on the issue**: started, failed and finished comments carry the draft release link, the run link and a per-target result table. The issue is closed automatically on success.
- **Only trusted requests run**: only `[build]` issues opened by the repository owner, organization members or collaborators are built; other issues cannot spend Actions minutes.
- **Cross-compilation for many targets** (table below); Apple targets can be lipo-merged into universal binaries.
- **Third-party libraries are built from source and linked statically**: x264, x265, libvpx, dav1d, SVT-AV1, libaom, Opus, LAME, Vorbis, WebP, zimg, SoX resampler, libass (with FreeType / HarfBuzz / FriBidi) and zlib. Versions are pinned, each library can be toggled on the page, and it can be shipped as a shared library instead.
- **Five package formats**: `tar.gz`, `zip`, NuGet (C++ / C#), Android AAR (with Prefab) and Apple XCFramework; merged formats can hold several architectures.
- **Packages work right after extraction**: rpaths / install names are fixed, `.pc` files use relative paths, and Windows static builds need no extra DLLs. Every package ships a CMake package config (`find_package(FFmpeg)`), `BUILDINFO.txt`, and the release contains `SHA256SUMS.txt`.
- **Fast rebuilds**: ccache for incremental builds, and the third-party library prefixes are cached in Actions.
- No repository names, user names or secrets are hard-coded, so a fork works without code changes.

## Repository layout

```text
deps/          one build recipe per third-party library (version, URL, SHA256, steps)
docs/          GitHub Pages front end + targets.json (platforms, architectures, runners, constraints)
scripts/       parameter parsing and validation, build, packaging, lipo merging
.github/       issue forms and the build-ffmpeg / build-deps workflows
```

## Targets

| Platform | Architectures | Notes |
|---|---|---|
| linux | x86_64, arm64, x86, armv7, armel, ppc64le, s390x, riscv64, mips64el, mipsel, loongarch64 | x86_64 / arm64 native (glibc 2.28+), the rest cross-compiled (glibc 2.31+, loongarch64 2.36+) |
| macos | x86_64, arm64, universal | native, macOS 11+ |
| windows | x86_64, x86, arm64 | llvm-mingw cross-compile, Windows 10+ |
| android | arm64-v8a, armeabi-v7a, x86_64, x86 | NDK r27d, API 21+ |
| ios / tvos / visionos | arm64 + simulators | Xcode; static libraries only, no ffmpeg / ffprobe programs |
| maccatalyst | arm64, x86_64, universal | Xcode, Mac Catalyst 14+ |
| freebsd | x86_64, arm64 | FreeBSD 14.4+ |
| wasm | wasm32 | Emscripten, single-threaded static libraries |

## Getting started

### 1. Fork and enable features

1. Fork the repository to your account (or an organization you can write to).
2. Open **Actions** and enable the workflows (they are disabled on forks).
3. **Settings → General → Features**: check **Issues**.
4. **Settings → Pages**: Source `Deploy from a branch`, the default branch, folder `/docs`.
5. After a minute or two the page is served at `https://<owner>.github.io/<repo>/`; it is also reachable from **Deployments → github-pages**.

### 2. Private source repositories (optional)

Skip this if the FFmpeg source is public. For a private repository, create a fine-grained PAT with `Contents: Read-only` and save it as the `SOURCE_PAT` secret under **Settings → Secrets and variables → Actions**. Without it the workflow's `GITHUB_TOKEN` cannot read private repositories.

### 3. Fill in the form and submit

| Field | Description |
|---|---|
| FFmpeg Git repository | a GitHub repository, HTTPS or SSH form |
| Branch / tag / commit | optional; commits need the full 40-character SHA |
| Package format | `tar.gz` / `zip` / NuGet / AAR / XCFramework |
| Target platform and architecture | options depend on platform and format |
| Build options | visual controls for build type, linking, license, programs and libraries, features and components, plus optional custom flags; the final configure flags are shown live |

Submitting opens GitHub's new-issue page prefilled; click **Submit new issue** and the workflow starts replying within seconds. You can skip the page and use **Issues → New issue** with the build template instead.

### 4. Get and use the package

Packages land in a **draft release** (visible to the owner and collaborators; click **Publish release** to make it public), and the run page keeps downloadable artifacts for 90 days.

Archives are named `ffmpeg-<platform>-<arch>-<license>-<build id>.zip`. After extraction:

```text
bin/            ffmpeg, ffprobe (plus DLLs on Windows)
lib/            static / shared libraries, pkgconfig/*.pc
include/        headers
share/          examples and man pages (depending on configure options)
BUILDINFO.txt   source repository, ref, commit, compiler, configure flags
```

- **Run it**: `./bin/ffmpeg -version` — shared builds have their rpath set, so no `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` is needed.
- **macOS first run blocked**: `xattr -dr com.apple.quarantine <extracted-dir>`.
- **As a library**: `export PKG_CONFIG_PATH=<extracted-dir>/lib/pkgconfig`.
- **CMake**: with `-DCMAKE_PREFIX_PATH=<extracted-dir>`, `find_package(FFmpeg REQUIRED COMPONENTS avformat)` provides `FFmpeg::avcodec`, `FFmpeg::avformat`, …; set `FFmpeg_USE_STATIC_LIBS=ON` to prefer static libraries.
- **Windows**: static builds are just the two executables and depend only on system DLLs; the static libraries (`libavcodec.a`, …) come from the MinGW toolchain, so MSVC projects should use a shared build.

Using the other formats:

- **NuGet**: package ID is `<owner>.FFmpeg.<license>.<RID or platform>`; C# projects just reference it (`runtimes/<rid>/native/` is copied to the output), C++ projects use `build/native/<id>.targets` for vcxproj.
- **AAR**: `implementation(files("libs/ffmpeg-....aar"))` then `System.loadLibrary("avcodec")`; NDK projects enable Prefab and link `ffmpeg::avformat`.
- **XCFramework**: reference it as an SPM `binaryTarget` or a CocoaPods `vendored_frameworks` entry; static slices link the `.a` files, shared slices need Embed & Sign.

### Alternative: run the workflow manually

**Actions → build-ffmpeg → Run workflow** accepts the same parameters. Results then appear only on the run page and under Releases, with no issue comments.

## Caveats

- **Configure flags are restricted**: only `[-+./:=,@%A-Za-z0-9_]` is allowed, so values with spaces or ``; & | $ > ` `` are rejected — `--extra-cflags="-O3 -march=native"` cannot be used. `--prefix` is rejected. Flags are not validated up front; a wrong one fails at the configure step and is reported on the issue.
- **Only the bundled libraries are available**: `--enable-lib...` flags without a recipe under `deps/` (e.g. `--enable-libfdk-aac`) fail at configure. Adding a library means adding `deps/NN-name.sh` (`DEP_VERSION`, `DEP_URL`, `DEP_SHA256`, `dep_build`).
- **Custom flags are appended last**, so they override earlier options; the workflow injects cross-compilation flags and `--cc=ccache` before yours.
- **GPL**: x264 and x265 are GPL and only available with the GPL license; GPL-only components are greyed out under LGPL.
- **No GPLv3 option**: no bundled component needs version3; add `--enable-version3` yourself if required.
- **Slim components**: `--disable-everything` plus per-category selections; the `file` protocol is always kept.
- **Runtime baselines**: glibc 2.28+ on Linux (2.31+ for non-x86_64 / arm64), macOS 11+, Windows 10+, Android API 21+, iOS / tvOS 13+, visionOS 1+.
- **Smoke tests** run only on Linux (natively or via qemu-user) and macOS; Windows, Android, Apple mobile, FreeBSD and WebAssembly cannot run on the build host.
- **No TLS on some targets**: Linux, Android, visionOS, Mac Catalyst, FreeBSD and WebAssembly builds have no TLS library, so `https` is unavailable; Windows uses Schannel and Apple platforms the system TLS.
- **x265 is 8-bit only**; **libass on Linux is built without fontconfig**, so fonts must come from subtitle attachments or the filter's `fontsdir`.
- **iOS / tvOS / visionOS / WASM** produce static libraries only and no ffmpeg / ffprobe programs; use the XCFramework format for frameworks.
- **NuGet** is always shared-linked; architectures are multi-select and packed into one `.nupkg`, with no universal option, and static-only platforms cannot be packaged.
- **AAR** is always shared-linked and contains no ffmpeg / ffprobe programs.
- **XCFramework** cannot mix static and shared in one package.
- **The first third-party build for a target takes 20–40 minutes**, then comes from the Actions cache; run the `build-deps` workflow once to warm it. Changing one recipe rebuilds only that library.
- **Editing a submitted issue does not start a new build** — submit a new issue instead; invalid parameters get a reply and the issue is closed.
- The page reads builds through the unauthenticated GitHub API, limited to **60 requests per hour**.
- Build issues in a public fork are visible to everyone, including the source URL and configure flags.
- The page must be opened as `https://<owner>.github.io/<repo>/`; a custom domain breaks repository detection.
- GitHub plans to retire the macOS Intel runners with the macOS 15 image in fall 2027; macOS x86_64 / universal will then need cross-compiling on arm64.

## License

MIT.
