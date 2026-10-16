# FreeType: font rendering (FTL / GPL-2.0). FFmpeg: --enable-libfreetype; used by libass.
DEP_VERSION=2.14.3
DEP_URL="https://downloads.sourceforge.net/project/freetype/freetype2/${DEP_VERSION}/freetype-${DEP_VERSION}.tar.xz"
DEP_SHA256=36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f
DEP_FEATURE=libass

dep_build() {
  fetch_source
  meson_build -Dzlib=enabled -Dbrotli=disabled -Dharfbuzz=disabled -Dpng=disabled -Dtests=disabled
}
