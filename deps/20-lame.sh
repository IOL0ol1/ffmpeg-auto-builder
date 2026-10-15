# LAME: MP3 encoder (LGPL-2.0-or-later). FFmpeg: --enable-libmp3lame.
DEP_VERSION=3.100
DEP_URL="https://downloads.sourceforge.net/project/lame/lame/${DEP_VERSION}/lame-${DEP_VERSION}.tar.gz"
DEP_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e

dep_build() {
  fetch_source
  update_config_scripts
  # lame_init_old is listed in the export file but not defined; it breaks some linkers.
  sed -i.bak '/lame_init_old/d' include/libmp3lame.sym
  local asm=()
  [[ "$TARGET_ARCH" == x86* ]] && asm=(--enable-nasm)
  autotools_build --disable-frontend --disable-decoder --disable-gtktest "${asm[@]}"
}
