#!/usr/bin/env python3
"""Run ASKI-91's actual Foundation-only sources in an isolated Swift package.

Does not build Aski or stand in for Apple-framework validation. The probe's
Swift 6.2 manifest permits portable checks; Aski itself still requires 6.3+.
Requires Python 3.8+, Swift 6.2+, and a NEW output directory with an existing parent.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ["PatternEvaluator", "OngoingPattern", "EntrancePattern", "AnimationAnchor", "AnimationEasing", "WaveDirection"]
TEST = "Tests/AskiTests/PatternFrameWorkContractTests.swift"
MANIFEST = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "AskiPatternProbe", targets: [
    .target(name: "Aski", swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "AskiTests", dependencies: ["Aski"], swiftSettings: [.swiftLanguageMode(.v6)])
])
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir
    report = {"status": "running", "native_aski_gate": "not_run", "inputs": {}}
    try:
        # Do not resolve an existing symlink into a new target directory.
        if output.exists() or output.is_symlink():
            raise ValueError("output directory must be new and must not be a symlink")
        output.mkdir(mode=0o700)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    try:
        package = output / "package"
        package.mkdir()
        (package / "Package.swift").write_text(MANIFEST, encoding="utf-8")
        paths = ["Sources/Aski/Animation/" + name + ".swift" for name in SOURCES] + [TEST]
        for relative in paths:
            source = ROOT / relative
            data = source.read_bytes()
            target = package / ("Tests/AskiTests" if relative == TEST else "Sources/Aski") / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            report["inputs"][relative] = hashlib.sha256(data).hexdigest()
        version = subprocess.run(["swift", "--version"], check=True, capture_output=True, text=True)
        report["swift"] = version.stdout.strip()
        command = ["swift", "test", "--package-path", str(package.resolve()), "-c", "release",
                   "-Xswiftc", "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors"]
        report["command"] = command
        with (output / "test.log").open("wb") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        report["exit_code"] = result.returncode
        report["status"] = "passed" if result.returncode == 0 else "failed"
        return result.returncode
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report.update(status="failed", error=str(error))
        return 1
    finally:
        (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("Pattern probe: " + report["status"] + "; native Aski gate not run", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
