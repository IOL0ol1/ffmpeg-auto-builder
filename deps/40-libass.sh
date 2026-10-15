# libass: ASS / SSA subtitle renderer (ISC). FFmpeg: --enable-libass (subtitles / ass filters).
# Uses DirectWrite on Windows and Core Text on macOS; on Linux fonts come from the files
# given to the filter (fontsdir), since fontconfig is not built.
DEP_VERSION=0.17.5
DEP_URL="https://github.com/libass/libass/releases/download/${DEP_VERSION}/libass-${DEP_VERSION}.tar.xz"
DEP_SHA256=2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc

dep_build() {
  fetch_source
  meson_build -Dfontconfig=disabled -Dlibunibreak=disabled -Drequire-system-font-provider=false \
    -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled -Dcheckasm=disabled
}
