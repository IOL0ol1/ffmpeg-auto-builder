# libvorbis: Vorbis audio codec (BSD-3-Clause). FFmpeg: --enable-libvorbis.
DEP_VERSION=1.3.7
DEP_URL="https://github.com/xiph/vorbis/releases/download/v${DEP_VERSION}/libvorbis-${DEP_VERSION}.tar.xz"
DEP_SHA256=b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b

dep_build() {
  fetch_source
  update_config_scripts
  # The macOS flag below is rejected by current Apple linkers.
  sed -i.bak 's/-force_cpusubtype_ALL//g' configure
  autotools_build --disable-docs --disable-examples --disable-oggtest
}
