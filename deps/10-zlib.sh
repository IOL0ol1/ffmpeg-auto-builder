# zlib: deflate compression (zlib license). Used by PNG, MOV, Matroska and others.
DEP_VERSION=1.3.2
DEP_URL="https://github.com/madler/zlib/releases/download/v${DEP_VERSION}/zlib-${DEP_VERSION}.tar.gz"
DEP_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
DEP_FEATURE=  # always built

dep_build() {
  fetch_source
  if [[ "$TARGET_PLATFORM" == "windows" ]]; then
    # win32/Makefile.gcc's install target also builds the DLL; install the static library by hand.
    make -f win32/Makefile.gcc libz.a CC="$CC" AR="$AR" RC="$WINDRES" CFLAGS="$CFLAGS -D_LARGEFILE64_SOURCE=1"
    install -Dm644 libz.a "$DEPS_PREFIX/lib/libz.a"
    install -Dm644 zlib.h "$DEPS_PREFIX/include/zlib.h"
    install -Dm644 zconf.h "$DEPS_PREFIX/include/zconf.h"
    mkdir -p "$DEPS_PREFIX/lib/pkgconfig"
    sed -e "s|@prefix@|$DEPS_PREFIX|" -e 's|@exec_prefix@|${prefix}|' -e 's|@libdir@|${exec_prefix}/lib|' \
      -e 's|@sharedlibdir@|${libdir}|' -e 's|@includedir@|${prefix}/include|' -e "s|@VERSION@|$DEP_VERSION|" \
      zlib.pc.in >"$DEPS_PREFIX/lib/pkgconfig/zlib.pc"
  else
    ./configure --prefix="$DEPS_PREFIX" --static
    make -j"$(cpu_count)"
    make install
  fi
}
