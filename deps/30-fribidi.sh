# GNU FriBidi: bidirectional text (LGPL-2.1-or-later). FFmpeg: --enable-libfribidi; used by libass.
DEP_VERSION=1.0.17
DEP_URL="https://github.com/fribidi/fribidi/releases/download/v${DEP_VERSION}/fribidi-${DEP_VERSION}.tar.xz"
DEP_SHA256=6949dcde27d41cebad1fd741fcafc36d55a1020d2d872d4a6eb3914caabbada2

dep_build() {
  fetch_source
  meson_build -Ddocs=false -Dbin=false -Dtests=false
}
