# libvorbis: Vorbis audio codec (BSD-3-Clause). FFmpeg: --enable-libvorbis.
DEP_VERSION=1.3.7
DEP_URL="https://github.com/xiph/vorbis/releases/download/v${DEP_VERSION}/libvorbis-${DEP_VERSION}.tar.xz"
DEP_SHA256=b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b

dep_build() {
  fetch_source
  update_config_scripts
  # Current Apple linkers reject -force_cpusubtype_ALL; clang rejects the GCC-only -mno-ieee-fp.
  sed -i.bak -e 's/-force_cpusubtype_ALL//g' -e 's/-mno-ieee-fp//g' configure
  autotools_build --disable-docs --disable-examples --disable-oggtest
}
