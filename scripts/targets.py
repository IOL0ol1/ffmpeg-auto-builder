"""Build targets from docs/targets.json for the workflow scripts.

  targets.py resolve <platform> <archs> <format> [static|shared]
      Validate a request; <archs> is one architecture, or a comma-separated list for NuGet;
      the last argument is the linkage of the third-party libraries.
      Prints key=value lines for $GITHUB_OUTPUT (archs, matrix, merges, needs_merge). On an
      invalid request prints "error<TAB>code<TAB>value<TAB>allowed values" and exits 2.
  targets.py all [platform]
      Matrix of every target that is built directly (no merged architectures).
  targets.py unavailable <platform> <arch>
      Library toggles (ids from docs/configure.js) the target cannot build.
  targets.py rids
      "<platform> <arch> <rid>" lines for the NuGet packer.
  targets.py platforms
      The platform ids.
"""
import json
import sys
from pathlib import Path

TARGETS = json.loads((Path(__file__).resolve().parent.parent / "docs" / "targets.json").read_text(encoding="utf-8"))
PLATFORMS = TARGETS["platforms"]


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


def nuget_capable(platform):
    return "shared" in PLATFORMS[platform].get("linkage", ["shared"])


def resolve(platform, arch_spec, package_format, deps_linkage="static"):
    if platform not in PLATFORMS:
        error("platform", platform, " / ".join(PLATFORMS))
    archs_of = PLATFORMS[platform]["archs"]
    nuget = package_format == "nuget"
    # The order of targets.json, without duplicates.
    requested = [arch for arch in arch_spec.split(",") if arch]
    allowed = [arch for arch in archs_of if not (nuget and "merge" in archs_of[arch])]
    for arch in requested:
        if arch not in allowed:
            error("arch", arch, " / ".join(allowed))
    archs = [arch for arch in allowed if arch in requested]
    if not archs:
        error("arch", arch_spec, " / ".join(allowed))
    if len(archs) > 1 and not nuget:
        error("archMulti", arch_spec)
    if nuget and not nuget_capable(platform):
        error("nugetPlatform", platform)
    if deps_linkage not in ("static", "shared"):
        error("depsLinkage", deps_linkage)
    if deps_linkage == "shared" and not nuget_capable(platform):
        error("depsShared", PLATFORMS[platform]["label"])

    include, merges = [], []
    for arch in archs:
        slices = archs_of[arch].get("merge")
        if slices:
            include += [entry(platform, part, slice_=True) for part in slices]
            merges.append({"platform": platform, "arch": arch, "slices": " ".join(slices)})
        else:
            include.append(entry(platform, arch))
    print(f"archs={'.'.join(archs)}")
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
    elif command == "rids":
        for p, spec in PLATFORMS.items():
            for a, arch in spec["archs"].items():
                if "rid" in arch:
                    print(p, a, arch["rid"])
    elif command == "platforms":
        print(" ".join(PLATFORMS))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
