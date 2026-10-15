# FFmpeg Auto Builder

English | [简体中文](README.zh-CN.md)

A template repository for building FFmpeg online with **GitHub Pages + GitHub Issues + GitHub Actions**. Fork it, enable Actions, Issues and Pages, and you get a visual FFmpeg build tool that runs entirely on GitHub — no third-party backend, and **no token is ever entered on the web page**.

## Features

- Fill in the source repository, branch/tag/commit, target platform, architecture, package format and configure options on the web page, and it generates a prefilled build issue.
- Submitting the issue on GitHub starts the build. Your GitHub sign-in is the only credential; the page never touches a token.
- Only build issues opened by the repository owner or collaborators are run, so other people's issues cannot spend your Actions minutes.
- The workflow comments on the issue when the build starts, fails or finishes, with links to the draft release and artifacts; GitHub notifies you according to your notification settings.
- Builds public FFmpeg repositories, and private FFmpeg forks once a `SOURCE_PAT` secret is configured.
- Linux / macOS / Windows builds run in parallel; macOS can produce an x86_64 + arm64 universal binary.
- Linux supports x86, arm64 and armv7; Windows supports x86_64, x86 and arm64 through MSYS2.
- ccache for incremental builds, a smoke test, and a single draft release per build (with `SHA256SUMS.txt`).
- Packages work right after extraction: shared builds get fixed rpaths / install names, `.pc` files use relative paths, Windows packages include the MinGW runtime DLLs, and every package contains `BUILDINFO.txt`.
- The page lists recent builds, their status and a job/step log summary.
- The page can be switched between **English / 简体中文 / 日本語** (defaults to the browser language); the generated issue and the workflow's replies use the same language.
- No repository names, user names or secrets are hard-coded, so a fork works without code changes.

## Repository layout

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/           # Build request issue forms (build.yml English / build-zh-CN.yml / build-ja.yml)
│   └── workflows/build.yml       # Build pipeline (setup → build matrix → lipo → release)
├── docs/                         # GitHub Pages site (index.html / app.js / configure.js / i18n.js / styles.css)
└── scripts/
    ├── common.sh                 # Shared helpers (repository URL parsing, flag filtering, ...)
    ├── parse-issue.py            # Parses build parameters from an issue body and detects its language
    ├── issue-comment.sh          # Posts the started / invalid / result replies in the issue's language
    ├── resolve-params.sh         # Validates parameters, creates the release tag and build matrix
    ├── install-deps.sh           # Installs Linux / macOS dependencies (apt / brew)
    ├── build-ffmpeg.sh           # Builds, fixes install paths, runs the smoke test and packages
    └── lipo-universal.sh         # Merges x86_64 + arm64 packages into a macOS universal binary
```

## Getting started

### Step 1: Fork and enable features

1. Click **Fork** to copy this repository to your account (or an organization you can write to).
2. **Enable Actions**: open the fork's **Actions** tab and click **I understand my workflows, go ahead and enable them** (Actions are disabled on forks by default).
3. **Enable Issues**: open **Settings → General → Features** and check **Issues** (Issues are disabled on forks by default).
4. **Enable Pages**: open **Settings → Pages** and under **Build and deployment** choose:
   - **Source**: `Deploy from a branch`
   - **Branch**: the default branch, **Folder**: `/docs`
5. After a minute or two the Pages URL appears at the top, e.g. `https://<your-user>.github.io/<repo>/`. Leave **Custom domain** empty.

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
| Target platform | `Linux` / `macOS` / `Windows` / `All platforms` | `Linux` |
| Target architecture | Depends on the platform; see the table below | `x86_64` |
| Package format | `tar.gz` or `zip` | `zip` |
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

Layout after extraction:

```text
bin/            ffmpeg, ffprobe (and DLLs on Windows)
lib/            static / shared libraries, pkgconfig/*.pc
include/        headers
share/          examples and man pages (depending on configure options)
BUILDINFO.txt   source repository, ref, commit, compiler, configure flags
```

- **Run directly**: `./bin/ffmpeg -version`. Shared builds have their rpath set (`$ORIGIN/../lib` on Linux, `@loader_path/../lib` on macOS), so no `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` is needed.
- **macOS**: if the first run is blocked because the developer cannot be verified, run `xattr -dr com.apple.quarantine <extracted-dir>`.
- **As a development library**: `export PKG_CONFIG_PATH=<extracted-dir>/lib/pkgconfig`; the `.pc` files use relative paths, so the directory can live anywhere.
- **Windows**: `bin/` includes `libwinpthread-1.dll` and the other MinGW runtime DLLs, so it runs without MSYS2.

### Alternative: run the workflow manually

Open **Actions → build-ffmpeg → Run workflow** and fill in the same parameters. Results then appear only on the Actions run page and under Releases; there are no issue comments.

## Platforms and architectures

| Platform | Architecture | Runner                       | Notes                                        |
|----------|--------------|------------------------------|----------------------------------------------|
| linux    | x86_64       | ubuntu-latest                | Native build                                 |
| linux    | x86          | ubuntu-latest                | `i686-linux-gnu` cross-compile               |
| linux    | arm64        | ubuntu-24.04-arm             | Native ARM runner                            |
| linux    | armv7        | ubuntu-latest                | `arm-linux-gnueabihf` cross-compile          |
| macos    | x86_64       | macos-15-intel               | Native build (minimum macOS 11)              |
| macos    | arm64        | macos-15                     | Native build (minimum macOS 11)              |
| macos    | universal    | macos-15-intel + macos-15    | Built separately, merged with lipo (including static libraries) |
| windows  | x86_64       | windows-latest               | MSYS2 MINGW64                                |
| windows  | x86          | windows-latest               | MSYS2 MINGW32 (experimental; see known limitations) |
| windows  | arm64        | windows-11-arm               | MSYS2 CLANGARM64, native ARM runner          |

> - "All platforms" builds Linux, macOS and Windows in parallel; combinations that do not apply (such as macOS + x86) are skipped.
> - `universal` builds x86_64 on Linux and Windows.
> - If some platforms fail, the successful packages are still published to the draft release.

## configure options

- Flags are separated by spaces or new lines and may only contain `[-+./:=,@%A-Za-z0-9_]`; values with `` ; & | $ > ` `` or spaces are rejected (so flags such as `--extra-cflags="-O3 -march=native"` cannot be used).
- The workflow injects cross-compilation flags and `--cc=ccache ...` **before** your flags; to override them, pass the same flag yourself (the later one wins).
- `--prefix` cannot be set: the install path is managed by the build, and the workflow rejects it.
- The build environment only has the toolchain needed for FFmpeg itself — **no third-party libraries such as x264, x265 or libvpx** — so flags like `--enable-libx264` fail at the configure step. To add them, edit `scripts/install-deps.sh` and the MSYS2 package lists in `scripts/resolve-params.sh` in your fork.

### Visual options on the page

The page turns common configure switches into visual controls and builds the flags in the order **build type / linking / license → programs & libraries → features → components → custom flags**, showing the final configure flags live (with a copy button). The current choices are saved in the browser and restored next time; **Reset** restores the defaults. Hover over an option to see its description and flags.

| Group | Options | Flags |
|---|---|---|
| Build type | **Release** (default) / RelWithDebInfo / Debug | `--disable-debug` / `--disable-stripping` / `--enable-debug=3 --disable-optimizations --disable-stripping` |
| Linking | **Static** (default) / Shared / Static + shared | `--enable-static --disable-shared` / `--enable-shared --disable-static` / both enabled |
| License | LGPL / **GPL** (default) | no flag / `--enable-gpl` |
| Programs & libraries | ffmpeg, ffprobe, libavdevice, libavfilter, libswscale, libswresample, docs | unchecking emits `--disable-<name>` (docs are off by default: `--disable-doc`) |
| Features | Assembly optimizations, hardware acceleration, network protocols, system library auto-detection, size optimization, PIC | `--disable-asm`, `--disable-hwaccels`, `--disable-network`, `--disable-autodetect`, `--enable-small`, `--enable-pic` |
| Components | **All components** (default) / Slim | slim: `--disable-everything` plus the checked `--enable-decoder=...`, `--enable-demuxer=...` and so on |

- **Slim components**: pick decoders, encoders, demuxers, muxers, parsers, bitstream filters, protocols and filters per category, each with **Select all / Clear / Common** shortcuts. Useful for embedded players, mobile apps and other size-sensitive uses.
- **Invalid combinations cannot be selected**: the page prevents bad configurations through the controls rather than validating afterwards:
  - **Linked dependencies**: disabling libavfilter also disables ffmpeg (which depends on it), and enabling ffmpeg enables libavfilter; the page shows a notice and highlights the linked option.
  - **License**: GPL-only components (such as the `hqdn3d`, `delogo`, `eq`, `cropdetect` and `mpdecimate` filters) carry a **GPL** badge and are greyed out under LGPL.
  - **Library dependencies**: with libswscale / libswresample disabled, the `scale` / `aresample` filters are greyed out in slim mode.
  - **Target platform**: the `https` protocol is unavailable for Linux targets (the Linux build environment has no TLS library).
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
   - restores the ccache cache and installs dependencies (a script on Linux/macOS, `msys2/setup-msys2` on Windows);
   - `scripts/build-ffmpeg.sh`: configure → make → make install → fix rpath / install names / `.pc` paths → bundle Windows runtime DLLs → `ffmpeg -version` smoke test (skipped when cross-compiling) → write `BUILDINFO.txt` → package;
   - uploads the artifact.
4. **lipo** (macOS universal only): merges executables, shared libraries and static libraries of both architectures.
5. **release**: collects every successful package, generates `SHA256SUMS.txt`, creates one draft release, then replies on the issue and closes it on success.

## Security

- **The page handles no tokens**: builds are triggered by issues you submit while signed in to github.com, and the page only reads public APIs, so no token can be phished or leaked through it.
- **Only trusted users' requests run**: anyone can open issues on a public repository, but the workflow only handles build issues from the owner, organization members and collaborators.
- **The private-source token lives in a secret**: `SOURCE_PAT` is only used inside the workflow, masked in logs, and no credentials are kept after checkout.
- **Strict input handling**: issue content is treated as untrusted, passed to scripts only through environment variables and never interpolated into shell commands; platform, architecture and format accept fixed values only, configure flags are limited to a safe character set, and source URLs must be `github.com` repositories.
- Build issues in a public repository are visible to everyone (including the source repository URL and configure flags). If that is not acceptable, make your fork private — the page's "Builds" list then cannot read it, so check Issues on GitHub instead.

## Known limitations

- **glibc version of Linux builds**: built on `ubuntu-latest`, the binaries need a recent glibc and may not run on older distributions (such as CentOS 7 or Ubuntu 20.04). For older systems, use `--enable-static --disable-shared` and build inside an older container in your fork.
- **Linux cross-compilation** (x86 / armv7) skips the smoke test and has no third-party libraries for the target architecture.
- **Windows x86 (MINGW32)**: MSYS2 is phasing out 32-bit environments, so the packages may disappear at any time.
- **Windows armv7** has been removed: MSYS2 no longer provides a usable 32-bit ARM environment.
- **macOS Intel**: GitHub plans to stop providing Intel runners when the macOS 15 image is retired in fall 2027; macOS x86_64 / universal will then need cross-compiling on arm64.
- The page must be opened as `https://<owner>.github.io/<repo>/` to detect the repository; it cannot with a custom domain.
- Editing a submitted issue does not start a new build; submit a new issue to change parameters.

## Ideas for extension

- Save several configure presets on the page
- Preinstall common third-party codec libraries (x264, x265, libvpx, libopus, ...)

## License

This repository is released under the **MIT License**, so it can be forked, customized and redistributed for personal or commercial use.
