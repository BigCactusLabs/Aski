#!/usr/bin/env python3
"""Run ASKI-88 pool-only experiments; no Apple API doubles or production edits.

Extracts the reviewed poolIndices declaration unchanged. Deliberately rejects
source drift: review the control before updating its Git blob pin. Python 3.8+.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "Sources/Aski/ShapeMatching.swift"
SOURCE_BLOB = "5c9d5882fc69b8ae242b4f608b4df5975d2cd8c5"
INPUTS = [
    SOURCE,
    "Tests/AskiTests/BrightnessPoolContractTests.swift",
    "Scripts/research/brightness-pool/SelectionArms.swift",
    "Scripts/research/brightness-pool/SelectionArmTests.swift",
    "Scripts/research/brightness-pool/Timing.swift",
    "Scripts/research/check-brightness-pool.py",
]
MANIFEST = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "BrightnessPoolProbe",
    targets: [
        .target(name: "Aski", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AskiTests", dependencies: ["Aski"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "BrightnessPoolTiming", dependencies: ["Aski"], swiftSettings: [.swiftLanguageMode(.v6)])
    ])
'''


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def extract_pool(data):
    blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    if blob != SOURCE_BLOB:
        raise ValueError("ShapeMatching.swift changed; review the frozen pool control before updating the pin")
    text = data.decode("utf-8")
    marker = "\n    /// Finds ranked character indices."
    prefix = "import simd\n\n"
    if text.count(marker) != 1 or not text.startswith(prefix + "public enum ShapeMatching {"):
        raise ValueError("reviewed pool extraction boundary not found")
    # No SIMD operation is involved in this one method. Remove the unused
    # module import, keep the declaration/body byte-for-byte, close its enum.
    return (text.split(marker)[0][len(prefix):] + "\n}\n").encode()


def create_output(path):
    if path.exists() or path.is_symlink():
        raise ValueError("output directory already exists or is a symlink")
    path.mkdir(mode=0o700)
    return path.resolve()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path, help="new retained directory; parent must exist")
    parser.add_argument("--swift", default="swift", help="compiler executable, not a shell command")
    parser.add_argument("--timing", action="store_true", help="also retain diagnostic CPU/wall timing CSV")
    parser.add_argument("--passes", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=500)
    args = parser.parse_args(argv)
    if args.passes < 5 or args.iterations < 1:
        parser.error("--passes must be >= 5 and --iterations must be positive")
    try:
        output = create_output(args.output_dir)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    report = {"schema_version": 1, "status": "running", "complete": False,
              "started_at": datetime.now(timezone.utc).isoformat(), "inputs": {}, "commands": [],
              "source_git_blob": SOURCE_BLOB, "scope": "extracted pool method only, not the native matcher",
              "adoption_verdict": "not_evaluated", "errors": []}

    def save():
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    def run(command, log):
        report["commands"].append({"argv": command, "log": log, "returncode": None})
        save()
        with (output / log).open("wb") as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=False)
        report["commands"][-1]["returncode"] = result.returncode
        if result.returncode:
            raise ValueError("command failed; see " + log)

    save()
    try:
        swift = shutil.which(args.swift)
        if swift is None:
            raise ValueError("Swift executable not found")
        run([swift, "--version"], "compiler.txt")
        inputs = {path: (ROOT / path).read_bytes() for path in INPUTS}
        report["inputs"] = {path: sha256(data) for path, data in inputs.items()}
        extracted = extract_pool(inputs[SOURCE])
        report["extracted_pool_sha256"] = sha256(extracted)
        package = output / "package"
        destinations = {
            "Sources/Aski/ShapeMatching.swift": extracted,
            "Sources/Aski/SelectionArms.swift": inputs[INPUTS[2]],
            "Tests/AskiTests/BrightnessPoolContractTests.swift": inputs[INPUTS[1]],
            "Tests/AskiTests/SelectionArmTests.swift": inputs[INPUTS[3]],
            "Sources/BrightnessPoolTiming/main.swift": inputs[INPUTS[4]],
            "Package.swift": MANIFEST.encode(),
        }
        for relative, data in destinations.items():
            path = package / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        run([swift, "test", "--package-path", str(package), "-c", "release", "--jobs", "2",
             "-Xswiftc", "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors"], "tests.log")
        if args.timing:
            # swift test builds the executable too; do not run another build.
            run([swift, "run", "--package-path", str(package), "-c", "release", "--skip-build",
                 "BrightnessPoolTiming", str(args.passes), str(args.iterations)], "timing.csv")
        for relative, data in inputs.items():
            if (ROOT / relative).read_bytes() != data:
                raise ValueError("input changed during probe: " + relative)
        report.update(status="valid", complete=True)
    except (OSError, ValueError, KeyboardInterrupt) as error:
        report["status"] = "invalid"
        report["errors"].append(str(error) or "interrupted")
    finally:
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        save()
    print(str(output / "report.json"))
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
