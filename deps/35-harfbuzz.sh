# HarfBuzz: text shaping (MIT). FFmpeg: --enable-libharfbuzz; used by libass.
DEP_VERSION=14.6.0
DEP_URL="https://github.com/harfbuzz/harfbuzz/releases/download/${DEP_VERSION}/harfbuzz-${DEP_VERSION}.tar.xz"
DEP_SHA256=d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586

dep_build() {
  fetch_source
  meson_build -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
    -Dchafa=disabled -Dicu=disabled -Dpng=disabled -Dzlib=disabled -Dtests=disabled -Ddocs=disabled -Dutilities=disabled \
    -Dintrospection=disabled
}
