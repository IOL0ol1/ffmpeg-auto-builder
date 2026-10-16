"""Combine the archives of Android ABIs (shared builds) into one Android Archive (AAR).

Usage: pack-aar.py <archives-dir> <output-dir>

Every ffmpeg-android-<arch>-*.zip archive in <archives-dir> becomes one ABI. The AAR holds
  jni/<abi>/*.so                    FFmpeg's (and shared third-party) libraries; Gradle
                                    packages them into the APK
  prefab/                           Prefab metadata, headers and libraries per FFmpeg
                                    library, so NDK projects can use
                                    find_package(ffmpeg CONFIG) with buildFeatures.prefab
plus AndroidManifest.xml and an empty classes.jar. The ffmpeg / ffprobe programs are not
part of it.

Environment: PACKAGE_OWNER, CONFIGURE_OPTIONS, RELEASE_TAG.
"""
import io
import json
import os
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

ABIS = {"arm64": "arm64-v8a", "armv7": "armeabi-v7a", "x86_64": "x86_64", "x86": "x86"}
# FFmpeg's libraries in dependency order.
MODULES = ["avutil", "swresample", "swscale", "postproc", "avcodec", "avformat", "avfilter", "avdevice"]
ARCHIVE_PATTERN = re.compile(r"^ffmpeg-android-([^-]+)-([^-]+)-.+\.zip$")
MIN_SDK = 21  # scripts/platforms/android.sh
NDK_MAJOR = 27


def fail(message):
    sys.exit(f"ERROR: {message}")


def license_id(configure):
    """gpl, lgpl, gplv3, lgplv3 or nonfree, following configure's last-wins handling."""
    state = {"gpl": False, "version3": False, "nonfree": False}
    for token in configure.split():
        match = re.fullmatch(r"--(enable|disable)-(gpl|version3|nonfree)", token)
        if match:
            state[match.group(2)] = match.group(1) == "enable"
    if state["nonfree"]:
        return "nonfree"
    return ("gpl" if state["gpl"] else "lgpl") + ("v3" if state["version3"] else "")


def requires(tree, module):
    """FFmpeg libraries a library depends on, from its pkg-config file."""
    pc = tree / "lib" / "pkgconfig" / f"lib{module}.pc"
    names = []
    for line in pc.read_text(encoding="utf-8").splitlines():
        if re.match(r"^Requires(\.private)?:", line):
            names += [name for name in re.findall(r"lib([a-z0-9_]+)", line.split(":", 1)[1]) if name in MODULES]
    return list(dict.fromkeys(names))


def version(tree):
    """Prefab wants a numeric version: the numeric part of FFmpeg's RELEASE ("8.0.git" -> 8.0)."""
    info = (tree / "BUILDINFO.txt").read_text(encoding="utf-8") if (tree / "BUILDINFO.txt").exists() else ""
    match = re.search(r"^ffmpeg_version: *(\d+(?:\.\d+)*)", info, re.M)
    return match.group(1) if match else "0"


def main():
    if len(sys.argv) != 3:
        fail("usage: pack-aar.py <archives-dir> <output-dir>")
    archives_dir, output_dir = Path(sys.argv[1]), Path(sys.argv[2])
    archives = {}
    for archive in sorted(archives_dir.rglob("*.zip")):
        match = ARCHIVE_PATTERN.match(archive.name)
        if match and match.group(1) in ABIS:
            archives[ABIS[match.group(1)]] = archive
    if not archives:
        fail(f"no Android archives found in {archives_dir}")

    owner = re.sub(r"[^a-z0-9_]", "", os.environ.get("PACKAGE_OWNER", "").lower()) or "ffmpegautobuilder"
    owner = owner if owner[0].isalpha() else f"x{owner}"
    configure = os.environ.get("CONFIGURE_OPTIONS", "")

    with tempfile.TemporaryDirectory() as temp:
        stage = Path(temp) / "aar"
        trees = {}
        for abi, archive in archives.items():
            tree = Path(temp) / "unpacked" / abi
            with zipfile.ZipFile(archive) as zf:
                zf.extractall(tree)
            trees[abi] = tree
            jni = stage / "jni" / abi
            jni.mkdir(parents=True)
            for lib in sorted((tree / "lib").glob("lib*.so")):
                shutil.copy2(lib, jni / lib.name)

        first = next(iter(trees.values()))
        modules = [m for m in MODULES if (first / "lib" / f"lib{m}.so").exists()]
        if not modules:
            fail("the archives contain no shared FFmpeg libraries (NuGet / AAR need shared linking)")

        prefab = stage / "prefab"
        prefab.mkdir()
        (prefab / "prefab.json").write_text(json.dumps(
            {"schema_version": 2, "name": "ffmpeg", "version": version(first), "dependencies": []}, indent=2))
        for module in modules:
            module_dir = prefab / "modules" / module
            (module_dir / "include").mkdir(parents=True)
            shutil.copytree(first / "include" / f"lib{module}", module_dir / "include" / f"lib{module}")
            (module_dir / "module.json").write_text(json.dumps({
                "export_libraries": [f":{dependency}" for dependency in requires(first, module)],
                "library_name": f"lib{module}",
            }, indent=2))
            for abi, tree in trees.items():
                libs = module_dir / "libs" / f"android.{abi}"
                libs.mkdir(parents=True)
                shutil.copy2(tree / "lib" / f"lib{module}.so", libs / f"lib{module}.so")
                (libs / "abi.json").write_text(json.dumps(
                    {"abi": abi, "api": MIN_SDK, "ndk": NDK_MAJOR, "stl": "none", "static": False}, indent=2))

        (stage / "AndroidManifest.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="io.github.{owner}.ffmpeg">\n'
            f'    <uses-sdk android:minSdkVersion="{MIN_SDK}" />\n'
            '</manifest>\n', encoding="utf-8")
        jar = io.BytesIO()
        with zipfile.ZipFile(jar, "w") as zf:
            zf.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\r\n\r\n")
        (stage / "classes.jar").write_bytes(jar.getvalue())
        (stage / "R.txt").write_text("")
        if (first / "BUILDINFO.txt").exists():
            shutil.copy2(first / "BUILDINFO.txt", stage / "BUILDINFO.txt")

        # ffmpeg-android-<archs>-<license>-<build id>.aar, like the other packages.
        tag = os.environ.get("RELEASE_TAG", "ffmpeg-android-unknown-build")
        match = re.match(r"^(ffmpeg-[^-]+-[^-]+)-(.+)$", tag)
        name = f"{match.group(1)}-{license_id(configure)}-{match.group(2)}.aar" if match else f"{tag}.aar"
        output_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output_dir / name, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(stage.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(stage).as_posix())

    print(f"Packed {name} for {', '.join(archives)}: {', '.join(modules)}")


if __name__ == "__main__":
    main()
