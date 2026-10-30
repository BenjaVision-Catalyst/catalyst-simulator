#!/usr/bin/env python3
"""Capture the exact native toolchain and linked-library identities."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("build", type=Path)
    parser.add_argument("repast", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    binaries = {}
    for name in ("catalyst_repast", "catalyst_value_tests"):
        path = args.build.resolve() / name
        linked = output("otool", "-L", str(path))
        libraries = {}
        for line in linked.splitlines()[1:]:
            target = Path(line.strip().split(" (")[0])
            if target.is_file():
                libraries[str(target.resolve())] = hashlib.sha256(target.read_bytes()).hexdigest()
        binaries[name] = dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                              file=output("file", str(path)), linked=linked, libraries=libraries)
    # Read receipts directly: provenance capture must not update Homebrew.
    dependencies = {}
    pending = [Path("/opt/homebrew/opt") / name for name in
               ("open-mpi", "boost", "boost-mpi", "openssl@3", "cmake", "ninja")]
    while pending:
        prefix = pending.pop().resolve()
        if str(prefix) in dependencies:
            continue
        receipt = prefix / "INSTALL_RECEIPT.json"
        data = json.loads(receipt.read_text())
        dependencies[str(prefix)] = dict(receipt=data, sha256=hashlib.sha256(receipt.read_bytes()).hexdigest())
        for dep in data.get("runtime_dependencies", []):
            recorded = Path("/opt/homebrew/Cellar") / dep["full_name"] / dep["pkg_version"]
            pending.append(recorded if recorded.exists() else Path("/opt/homebrew/opt") / dep["full_name"])
    report = dict(platform=platform.platform(), machine=platform.machine(),
                  compiler=output("/usr/bin/clang++", "--version"),
                  sdk=output("xcrun", "--show-sdk-path"), sdkVersion=output("xcrun", "--show-sdk-version"),
                  cmake=output("cmake", "--version"), ninja=output("ninja", "--version"),
                  mpi=output("/opt/homebrew/bin/mpirun", "--version"),
                  repastRevision=output("git", "-C", str(args.repast), "rev-parse", "HEAD"),
                  repastDirty=output("git", "-C", str(args.repast), "status", "--porcelain"),
                  upstreamCpp=28, excluded=["NCDataSet.cpp", "NCDataSetBuilder.cpp"],
                  openMP=False, dependencies=dependencies, binaries=binaries,
                  cmakeCache=(args.build / "CMakeCache.txt").read_text())
    source = Path(__file__).resolve().parent
    files = [source / "CMakeLists.txt", *source.glob("*.hpp"), *source.glob("*.cpp"),
             *source.glob("*.py"), *source.glob("*.st"), *source.glob("gemstone/*.topaz")]
    report["sourceSha256"] = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sorted(files)}
    assert report["repastDirty"] == ""
    args.destination.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
