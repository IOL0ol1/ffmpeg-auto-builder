# libogg: Ogg container library (BSD-3-Clause), needed by libvorbis.
DEP_VERSION=1.3.6
DEP_URL="https://github.com/xiph/ogg/releases/download/v${DEP_VERSION}/libogg-${DEP_VERSION}.tar.xz"
DEP_SHA256=5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061

dep_build() {
  fetch_source
  update_config_scripts
  autotools_build
}
