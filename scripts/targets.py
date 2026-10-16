"""Build targets from docs/targets.json for the workflow scripts.

  targets.py resolve <platform> <archs> <format> [static|shared]
      Validate a request. <archs> is one architecture; NuGet and AAR take a comma-separated
      list, and the XCFramework pseudo platform "apple" a list of <platform>_<arch> targets.
      The last argument is the linkage of the third-party libraries.
      Prints key=value lines for $GITHUB_OUTPUT (archs, matrix, merges, needs_merge). On an
      invalid request prints "error<TAB>code<TAB>value<TAB>allowed values" and exits 2.
  targets.py all [platform]
      Matrix of every target that is built directly (no merged architectures).
  targets.py unavailable <platform> <arch>
      Library toggles (ids from docs/configure.js) the target cannot build.
  targets.py platforms
      The platform ids.
"""
import json
import sys
from pathlib import Path

TARGETS = json.loads((Path(__file__).resolve().parent.parent / "docs" / "targets.json").read_text(encoding="utf-8"))
PLATFORMS = TARGETS["platforms"]
# Formats that combine several architectures (or targets) into one package.
MULTI_FORMATS = ("nuget", "aar", "xcframework")
XCFRAMEWORK_PLATFORM = "apple"


def error(code, value, allowed=""):
    print(f"error\t{code}\t{value}\t{allowed}")
    sys.exit(2)


def entry(platform, arch, slice_=False):
    spec = PLATFORMS[platform]["archs"][arch]
    return {
        "platform": platform,
        "arch": arch,
        "os": spec["runner"],
        "container": spec.get("container", ""),
        # scripts/platforms/<toolchain>.sh; several platforms can share one.
        "toolchain": PLATFORMS[platform].get("toolchain", platform),
        "slice": "true" if slice_ else "",
    }


def shared_capable(platform, package_format):
    """Whether the target can use shared libraries in this package format."""
    if package_format == "xcframework":
        return True  # as .framework bundles
    return "shared" in PLATFORMS[platform].get("linkage", ["shared"])


def requested(spec):
    return [item for item in spec.split(",") if item]


def resolve_xcframework(target_spec):
    """[(platform, arch)] of an XCFramework request, in targets.json order."""
    allowed = [(p, a) for p, spec in PLATFORMS.items() if spec.get("xcframework")
               for a, arch in spec["archs"].items() if "merge" not in arch]
    names = [f"{p}_{a}" for p, a in allowed]
    for item in requested(target_spec):
        if item not in names:
            error("arch", item, " / ".join(names))
    targets = [target for target, name in zip(allowed, names) if name in requested(target_spec)]
    if not targets:
        error("arch", target_spec, " / ".join(names))
    return targets


def resolve(platform, arch_spec, package_format, deps_linkage="static"):
    if (platform == XCFRAMEWORK_PLATFORM) != (package_format == "xcframework"):
        error("xcframeworkPlatform", platform)
    if package_format == "aar" and platform != "android":
        error("aarPlatform", platform)
    if deps_linkage not in ("static", "shared"):
        error("depsLinkage", deps_linkage)

    if package_format == "xcframework":
        targets = resolve_xcframework(arch_spec)
        archs_label = "xcframework"
    else:
        if platform not in PLATFORMS:
            error("platform", platform, " / ".join(PLATFORMS))
        archs_of = PLATFORMS[platform]["archs"]
        multi = package_format in MULTI_FORMATS
        allowed = [arch for arch in archs_of if not (multi and "merge" in archs_of[arch])]
        for arch in requested(arch_spec):
            if arch not in allowed:
                error("arch", arch, " / ".join(allowed))
        archs = [arch for arch in allowed if arch in requested(arch_spec)]
        if not archs:
            error("arch", arch_spec, " / ".join(allowed))
        if len(archs) > 1 and not multi:
            error("archMulti", arch_spec)
        if package_format == "nuget" and not shared_capable(platform, package_format):
            error("nugetPlatform", platform)
        targets = [(platform, arch) for arch in archs]
        # The release tag lists the architectures.
        archs_label = ".".join(archs)

    for target_platform, _ in targets:
        if deps_linkage == "shared" and not shared_capable(target_platform, package_format):
            error("depsShared", PLATFORMS[target_platform]["label"])

    include, merges = [], []
    for target_platform, arch in targets:
        slices = PLATFORMS[target_platform]["archs"][arch].get("merge")
        if slices:
            include += [entry(target_platform, part, slice_=True) for part in slices]
            merges.append({"platform": target_platform, "arch": arch, "slices": " ".join(slices)})
        else:
            include.append(entry(target_platform, arch))
    print(f"archs={archs_label}")
    print(f"targets={','.join(f'{p}_{a}' for p, a in targets) if package_format == 'xcframework' else ','.join(a for _, a in targets)}")
    print(f"matrix={json.dumps({'include': include}, separators=(',', ':'))}")
    print(f"merges={json.dumps({'include': merges}, separators=(',', ':'))}")
    print(f"needs_merge={'true' if merges else 'false'}")


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    if command == "resolve" and len(argv) in (5, 6):
        resolve(*argv[2:])
    elif command == "all":
        only = argv[2] if len(argv) > 2 else ""
        include = [entry(p, a) for p, spec in PLATFORMS.items() if not only or p == only
                   for a, arch in spec["archs"].items() if "merge" not in arch]
        print(json.dumps({"include": include}, separators=(",", ":")))
    elif command == "unavailable" and len(argv) == 4:
        print(" ".join(PLATFORMS.get(argv[2], {}).get("archs", {}).get(argv[3], {}).get("unavailable", [])))
    elif command == "platforms":
        print(" ".join(PLATFORMS))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
