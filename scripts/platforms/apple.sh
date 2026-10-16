# Apple device, simulator and Mac Catalyst targets (platforms ios, tvos, visionos and
# maccatalyst share this file), sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain). Cross-compiled with Xcode's clang on an Apple
# Silicon runner; the compilers are wrapped so that every build system gets the same
# -target / -isysroot. Minimum versions: iOS / tvOS 13.0, visionOS 1.0, Mac Catalyst 14.0.

# Sets the caller's sdk, target (clang target triple), clang_arch, cpu_family, ffmpeg_arch,
# host (autotools), cmake_system and min_version.
apple_target() {
  local arch="$TARGET_ARCH" simulator=""
  if [[ "$arch" == sim_* ]]; then
    simulator="-simulator"
    arch="${arch#sim_}"
  fi
  case "$arch" in
    arm64)  clang_arch=arm64  cpu_family=aarch64 ffmpeg_arch=aarch64 host=aarch64-apple-darwin ;;
    x86_64) clang_arch=x86_64 cpu_family=x86_64  ffmpeg_arch=x86_64  host=x86_64-apple-darwin ;;
    *) return 1 ;;
  esac
  case "$TARGET_PLATFORM" in
    ios)
      sdk=$([[ -n "$simulator" ]] && echo iphonesimulator || echo iphoneos)
      min_version=13.0 target="$clang_arch-apple-ios$min_version$simulator" cmake_system=iOS ;;
    tvos)
      sdk=$([[ -n "$simulator" ]] && echo appletvsimulator || echo appletvos)
      min_version=13.0 target="$clang_arch-apple-tvos$min_version$simulator" cmake_system=tvOS ;;
    visionos)
      sdk=$([[ -n "$simulator" ]] && echo xrsimulator || echo xros)
      min_version=1.0 target="$clang_arch-apple-xros$min_version$simulator" cmake_system=visionOS ;;
    maccatalyst)
      # iOS code running on macOS: the macOS SDK with the iOS support frameworks.
      sdk=macosx min_version=14.0 target="$clang_arch-apple-ios$min_version-macabi" cmake_system=Darwin ;;
    *) return 1 ;;
  esac
}

platform_install() {
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    brew install nasm pkg-config ccache meson ninja automake autoconf libtool
}

platform_toolchain() {
  local sdk target clang_arch cpu_family ffmpeg_arch host cmake_system min_version
  apple_target || fail "Unsupported target: $TARGET_PLATFORM/$TARGET_ARCH"
  # The workflow sets it for macOS; here it would make CMake add -mmacosx-version-min.
  unset MACOSX_DEPLOYMENT_TARGET

  local sdk_path dir extra=""
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  dir="$DEPS_PREFIX/../toolchain"
  mkdir -p "$dir"
  if [[ "$TARGET_PLATFORM" == maccatalyst ]]; then
    extra="-iframework $sdk_path/System/iOSSupport/System/Library/Frameworks"
    extra+=" -isystem $sdk_path/System/iOSSupport/usr/include -L$sdk_path/System/iOSSupport/usr/lib"
  fi
  local tool
  for tool in clang clang++; do
    printf '#!/bin/sh\nexec "%s" -target %s -isysroot "%s" %s "$@"\n' \
      "$(xcrun --sdk "$sdk" -f "$tool")" "$target" "$sdk_path" "$extra" >"$dir/$tool"
    chmod +x "$dir/$tool"
  done
  export CC="$dir/clang" CXX="$dir/clang++"
  AR="$(xcrun --sdk "$sdk" -f ar)" RANLIB="$(xcrun --sdk "$sdk" -f ranlib)"
  NM="$(xcrun --sdk "$sdk" -f nm)" STRIP="$(xcrun --sdk "$sdk" -f strip)"
  export AR RANLIB NM STRIP
  TARGET_RUNNER="none"
  AUTOTOOLS_HOST_ARGS=(--host="$host")
  write_cross_files Darwin "$cpu_family" "$cpu_family" "$CC" "$CXX" "$AR" "$STRIP"
  {
    echo "set(CMAKE_SYSTEM_NAME $cmake_system)"
    echo "set(CMAKE_OSX_SYSROOT $sdk_path)"
    echo "set(CMAKE_OSX_ARCHITECTURES $clang_arch)"
    [[ "$TARGET_PLATFORM" == maccatalyst ]] || echo "set(CMAKE_OSX_DEPLOYMENT_TARGET $min_version)"
  } >>"$dir/cross.cmake"
  FFMPEG_TOOLCHAIN_ARGS=(
    "--target-os=darwin"
    "--arch=$ffmpeg_arch"
    "--enable-cross-compile"
    "--cc=$CC"
    "--cxx=$CXX"
    "--ar=$AR"
    "--ranlib=$RANLIB"
    "--nm=$NM"
    "--strip=$STRIP"
  )
}
