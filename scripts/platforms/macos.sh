# macOS targets, sourced by scripts/install-deps.sh (platform_install) and
# scripts/toolchain.sh (platform_toolchain): native builds on a runner of that architecture.

platform_install() {
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    brew install nasm pkg-config ccache meson ninja automake autoconf libtool
}

platform_toolchain() {
  export CC=clang CXX=clang++
  export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
}
