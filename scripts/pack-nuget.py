"""Combine per-platform build archives into one NuGet package.

Usage: pack-nuget.py <archives-dir> <output-dir>

Every ffmpeg-<platform>-<arch>-*.zip (or .tar.gz) archive in <archives-dir> becomes one
runtime identifier (RID). The package contains, per RID:
  build/native/<rid>/       the complete install tree (headers, libraries, binaries,
                            pkg-config files, BUILDINFO.txt) as in the zip output
  runtimes/<rid>/native/    executables and shared libraries, copied to the output of
                            .NET projects automatically
plus build/native/<id>.targets for C++ (vcxproj) projects on Windows.

Environment: PACKAGE_OWNER, RUN_NUMBER, CONFIGURE_OPTIONS, SOURCE_REPOSITORY,
SOURCE_COMMIT (optional), RELEASE_TAG.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape

RIDS = {
    ("linux", "x86_64"): "linux-x64",
    ("linux", "x86"): "linux-x86",
    ("linux", "arm64"): "linux-arm64",
    ("linux", "armv7"): "linux-arm",
    ("macos", "x86_64"): "osx-x64",
    ("macos", "arm64"): "osx-arm64",
    ("windows", "x86_64"): "win-x64",
    ("windows", "x86"): "win-x86",
    ("windows", "arm64"): "win-arm64",
}
# MSBuild $(Platform) values of C++ projects for each Windows RID.
MSBUILD_PLATFORMS = {"win-x64": ["x64"], "win-x86": ["Win32", "x86"], "win-arm64": ["ARM64"]}
ARCHIVE_PATTERN = re.compile(r"^ffmpeg-(linux|macos|windows)-(x86_64|x86|arm64|armv7)-.+\.(zip|tar\.gz)$")


def fail(message):
    sys.exit(f"ERROR: {message}")


def extract(archive, destination):
    destination.mkdir(parents=True)
    if archive.name.endswith(".zip"):
        subprocess.run(["unzip", "-q", str(archive), "-d", str(destination)], check=True)
    else:
        subprocess.run(["tar", "-xzf", str(archive), "-C", str(destination)], check=True)


def is_runtime_file(path):
    """Executables and shared libraries a running program needs (not import/static libs)."""
    name = path.name
    if path.parent.name == "bin":
        return not name.endswith((".lib", ".def", ".a"))
    # Shared libraries under their runtime (SONAME / install) names.
    return bool(re.fullmatch(r"lib[^.]+\.so\.\d+", name) or re.fullmatch(r"lib[^.]+\.\d+\.dylib", name))


def read_buildinfo(root):
    info = {}
    path = root / "BUILDINFO.txt"
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition(": ")
            info[key.strip()] = value.strip()
    return info


def package_version(ffmpeg_version, run_number):
    """FFmpeg's RELEASE ("8.0.git", "7.1", "7.1.1") plus the run number as a 4th part."""
    parts = re.findall(r"\d+", ffmpeg_version or "")[:3]
    parts += ["0"] * (3 - len(parts))
    return ".".join(parts + [str(run_number)])


def license_expression(configure):
    """Follow configure's last-wins handling of --enable/--disable-gpl/version3/nonfree."""
    state = {"gpl": False, "version3": False, "nonfree": False}
    for token in configure.split():
        match = re.fullmatch(r"--(enable|disable)-(gpl|version3|nonfree)", token)
        if match:
            state[match.group(2)] = match.group(1) == "enable"
    if state["nonfree"]:
        return None
    if state["gpl"]:
        return "GPL-3.0-or-later" if state["version3"] else "GPL-2.0-or-later"
    return "LGPL-3.0-or-later" if state["version3"] else "LGPL-2.1-or-later"


def write_targets(path, package_id, windows_import_libs):
    """MSBuild integration for C++ projects: include path, import libraries, DLL copy."""
    rid_lines = []
    for rid, platforms in MSBUILD_PLATFORMS.items():
        condition = " Or ".join(f"'$(Platform)' == '{platform}'" for platform in platforms)
        rid_lines.append(f"    <FFmpegRid Condition=\"'$(FFmpegRid)' == '' And ({condition})\">{rid}</FFmpegRid>")
    lib_groups = []
    for rid, libs in sorted(windows_import_libs.items()):
        if libs:
            lib_groups.append(
                f"  <ItemDefinitionGroup Condition=\"'$(FFmpegRid)' == '{rid}'\">\n"
                f"    <Link>\n"
                f"      <AdditionalDependencies>{';'.join(libs)};%(AdditionalDependencies)</AdditionalDependencies>\n"
                f"    </Link>\n"
                f"  </ItemDefinitionGroup>"
            )
    content = f"""<?xml version="1.0" encoding="utf-8"?>
<!-- C++ (vcxproj) integration for {package_id}. Set FFmpegRid to override the RID selection. -->
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
{chr(10).join(rid_lines)}
    <FFmpegRoot>$(MSBuildThisFileDirectory)$(FFmpegRid)\\</FFmpegRoot>
    <FFmpegRuntimeDir>$(MSBuildThisFileDirectory)..\\..\\runtimes\\$(FFmpegRid)\\native\\</FFmpegRuntimeDir>
    <FFmpegAvailable Condition="'$(FFmpegRid)' != '' And Exists('$(FFmpegRoot)include')">true</FFmpegAvailable>
  </PropertyGroup>
  <ItemDefinitionGroup Condition="'$(FFmpegAvailable)' == 'true'">
    <ClCompile>
      <AdditionalIncludeDirectories>$(FFmpegRoot)include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
      <!-- FFmpeg headers require this when included from C++. -->
      <PreprocessorDefinitions>__STDC_CONSTANT_MACROS;%(PreprocessorDefinitions)</PreprocessorDefinitions>
    </ClCompile>
    <Link>
      <AdditionalLibraryDirectories>$(FFmpegRoot)bin;$(FFmpegRoot)lib;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
    </Link>
  </ItemDefinitionGroup>
{chr(10).join(lib_groups)}
  <Target Name="FFmpegCopyRuntime" AfterTargets="Build" Condition="'$(FFmpegAvailable)' == 'true'">
    <ItemGroup>
      <FFmpegRuntimeFile Include="$(FFmpegRuntimeDir)*.dll" />
    </ItemGroup>
    <Copy SourceFiles="@(FFmpegRuntimeFile)" DestinationFolder="$(OutDir)" SkipUnchangedFiles="true" />
  </Target>
</Project>
"""
    path.write_text(content, encoding="utf-8")


def write_readme(path, package_id, version, rids, configure, buildinfo):
    rows = "\n".join(f"| `{rid}` | `build/native/{rid}/` | `runtimes/{rid}/native/` |" for rid in rids)
    path.write_text(f"""# {package_id}

FFmpeg {buildinfo.get('ffmpeg_version', '')} native binaries built by
[ffmpeg-auto-builder](https://github.com/{os.environ.get('GITHUB_REPOSITORY', '')}).

- Source: {buildinfo.get('source_repository', '')} @ {buildinfo.get('source_commit', '') or buildinfo.get('source_ref', '')}
- configure: `{configure}`

| RID | Complete files (headers, libraries, binaries, BUILDINFO.txt) | Runtime files |
|---|---|---|
{rows}

## C# / .NET

Executables and shared libraries in `runtimes/<rid>/native/` are copied to the build output
automatically. Load the libraries by their versioned names (for example with FFmpeg.AutoGen):
`avcodec-NN.dll` on Windows, `libavcodec.so.NN` on Linux, `libavcodec.NN.dylib` on macOS.
Shared libraries are only included when the package was built with shared linking. On Linux
and macOS, mark `ffmpeg` / `ffprobe` executable (`chmod +x`) before running them.

## C++

Visual C++ projects (vcxproj) on Windows get the include directory, the import libraries and
the DLL copy automatically for x64, Win32 and ARM64 (set `FFmpegRid` to override). Linking
from MSVC requires a package built with shared linking. Other build systems can use
`build/native/<rid>/include`, `build/native/<rid>/lib` and the pkg-config files in
`build/native/<rid>/lib/pkgconfig`.

Package version {version}.
""", encoding="utf-8")


def write_nuspec(path, package_id, version, rids, configure, buildinfo):
    license_value = license_expression(configure)
    license_xml = f'<license type="expression">{license_value}</license>' if license_value else ""
    repository = buildinfo.get("source_repository", "")
    commit = buildinfo.get("source_commit", "")
    description = (
        f"FFmpeg {buildinfo.get('ffmpeg_version', '')} native binaries for {', '.join(rids)}, "
        f"usable from C++ and .NET projects. configure: {configure}"
    )
    path.write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>{escape(package_id)}</id>
    <version>{version}</version>
    <authors>{escape(os.environ.get('PACKAGE_OWNER', 'ffmpeg-auto-builder'))}</authors>
    <description>{escape(description)}</description>
    {license_xml}
    <projectUrl>https://ffmpeg.org/</projectUrl>
    <repository type="git" url="{escape(repository)}" commit="{escape(commit)}" />
    <readme>README.md</readme>
    <tags>ffmpeg native {' '.join(rids)}</tags>
    <dependencies>
      <group targetFramework="native" />
      <group targetFramework="netstandard2.0" />
    </dependencies>
  </metadata>
  <files>
    <!-- NuGet versions disagree on how "dir/**" maps to the target (some keep "dir/", some
         drop it); "**" from the staging root keeps every path as staged in all of them. -->
    <file src="**" exclude="*.nuspec" target="" />
  </files>
</package>
""", encoding="utf-8")


def main():
    if len(sys.argv) != 3:
        fail("usage: pack-nuget.py <archives-dir> <output-dir>")
    archives_dir, output_dir = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
    owner = os.environ.get("PACKAGE_OWNER", "").strip() or "ffmpeg-auto-builder"
    package_id = re.sub(r"[^A-Za-z0-9._-]", "", owner) + ".FFmpeg"
    configure = os.environ.get("CONFIGURE_OPTIONS", "")

    archives = {}
    for archive in sorted(archives_dir.rglob("*")):
        match = ARCHIVE_PATTERN.match(archive.name)
        if match and (match.group(1), match.group(2)) in RIDS:
            archives[RIDS[(match.group(1), match.group(2))]] = archive
    if not archives:
        fail(f"no platform archives found in {archives_dir}")

    with tempfile.TemporaryDirectory() as temp:
        stage = Path(temp) / "stage"
        windows_import_libs = {}
        buildinfo = {}
        for rid, archive in sorted(archives.items()):
            unpacked = Path(temp) / "unpacked" / rid
            extract(archive, unpacked)
            # copytree follows symlinks by default, so library symlinks become real files.
            tree = stage / "build" / "native" / rid
            shutil.copytree(unpacked, tree)
            buildinfo = buildinfo or read_buildinfo(tree)

            runtime = stage / "runtimes" / rid / "native"
            runtime.mkdir(parents=True)
            for folder in ("bin", "lib"):
                for file in sorted((tree / folder).glob("*")) if (tree / folder).is_dir() else []:
                    if file.is_file() and is_runtime_file(file):
                        shutil.copy2(file, runtime / file.name)

            if rid in MSBUILD_PLATFORMS:
                windows_import_libs[rid] = sorted(p.name for p in (tree / "bin").glob("*.lib")) if (tree / "bin").is_dir() else []

        rids = sorted(archives)
        version = package_version(buildinfo.get("ffmpeg_version"), os.environ.get("RUN_NUMBER", "0"))

        # An empty lib/ asset marks the package as compatible with .NET projects.
        placeholder = stage / "lib" / "netstandard2.0" / "_._"
        placeholder.parent.mkdir(parents=True)
        placeholder.touch()
        write_targets(stage / "build" / "native" / f"{package_id}.targets", package_id, windows_import_libs)
        write_readme(stage / "README.md", package_id, version, rids, configure, buildinfo)
        write_nuspec(stage / f"{package_id}.nuspec", package_id, version, rids, configure, buildinfo)

        project = Path(temp) / "pack" / "pack.csproj"
        project.parent.mkdir()
        project.write_text("""<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <NoWarn>$(NoWarn);NU5100;NU5128</NoWarn>
  </PropertyGroup>
</Project>
""", encoding="utf-8")
        output_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            "dotnet", "pack", str(project), "-c", "Release", "--nologo", "-o", str(output_dir),
            f"-p:NuspecFile={stage / f'{package_id}.nuspec'}",
            f"-p:NuspecBasePath={stage}",
        ], check=True)

    print(f"Packed {package_id} {version} for {', '.join(rids)}")


if __name__ == "__main__":
    main()
