# Android targets, sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain): cross-compiled on Ubuntu with the Android NDK
# for API level 21 (Android 5.0), the oldest the NDK supports. The C++ runtime is linked
# statically (libc++_static), so the results only depend on system libraries.

ANDROID_NDK_VERSION=27.3.13750724  # r27d, long-term support
ANDROID_API=21

# Sets the caller's triple (clang target prefix), host (autotools), cpu_family, cpu and
# ffmpeg_arch for an architecture.
android_target() {
  case "$1" in
    arm64)  triple=aarch64-linux-android     host=aarch64-linux-android   cpu_family=aarch64 cpu=armv8-a ffmpeg_arch=aarch64 ;;
    armv7)  triple=armv7a-linux-androideabi  host=arm-linux-androideabi   cpu_family=arm     cpu=armv7-a ffmpeg_arch=arm ;;
    x86_64) triple=x86_64-linux-android      host=x86_64-linux-android    cpu_family=x86_64  cpu=x86_64  ffmpeg_arch=x86_64 ;;
    x86)    triple=i686-linux-android        host=i686-linux-android      cpu_family=x86     cpu=i686    ffmpeg_arch=x86 ;;
    *) return 1 ;;
  esac
}

android_abi() {
  case "$1" in
    arm64) echo arm64-v8a ;; armv7) echo armeabi-v7a ;; x86_64) echo x86_64 ;; x86) echo x86 ;;
  esac
}

platform_install() {
  sudo apt-get update
  sudo apt-get install -y nasm pkg-config ccache zip unzip automake autoconf libtool cmake pipx patchelf
  install_python_build_tools

  # GitHub's Ubuntu images ship the Android SDK with several NDKs; install the pinned one
  # when it is missing.
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
  local ndk="$sdk/ndk/$ANDROID_NDK_VERSION"
  if [[ ! -x "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]]; then
    yes | "$sdk/cmdline-tools/latest/bin/sdkmanager" --install "ndk;$ANDROID_NDK_VERSION" >/dev/null
  fi
  export_env ANDROID_NDK "$ndk"
}

platform_toolchain() {
  require_env ANDROID_NDK
  local triple host cpu_family cpu ffmpeg_arch
  android_target "$TARGET_ARCH" || fail "Unsupported target: android/$TARGET_ARCH"
  local bin="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
  export PATH="$bin:$PATH"
  export CC="$bin/$triple$ANDROID_API-clang" CXX="$bin/$triple$ANDROID_API-clang++"
  export AR="$bin/llvm-ar" RANLIB="$bin/llvm-ranlib" NM="$bin/llvm-nm" STRIP="$bin/llvm-strip"
  TARGET_RUNNER="none"
  AUTOTOOLS_HOST_ARGS=(--host="$host")
  write_cross_files Android "$cpu_family" "$cpu" "$CC" "$CXX" "$AR" "$STRIP"
  # CMake projects use the NDK's own toolchain file, which knows the ABI details.
  CMAKE_TOOLCHAIN_ARGS=(
    "-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake"
    "-DANDROID_ABI=$(android_abi "$TARGET_ARCH")"
    "-DANDROID_PLATFORM=android-$ANDROID_API"
    "-DANDROID_STL=c++_static"
    "-DCMAKE_FIND_ROOT_PATH=$DEPS_PREFIX"
  )
  FFMPEG_TOOLCHAIN_ARGS=(
    "--target-os=android"
    "--arch=$ffmpeg_arch"
    "--enable-cross-compile"
    "--cc=$CC"
    "--cxx=$CXX"
    "--ar=$AR"
    "--ranlib=$RANLIB"
    "--nm=$NM"
    "--strip=$STRIP"
  )
  # armeabi-v7a includes NEON since NDK r21.
  [[ "$TARGET_ARCH" != armv7 ]] || FFMPEG_TOOLCHAIN_ARGS+=("--cpu=armv7-a" "--enable-neon")
}
