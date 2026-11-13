#!/usr/bin/env bash
# Standalone Swift core checks. Does not build Aski's Apple-framework pipeline.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
mode="${1:-test}"
if [[ "$mode" != test && "$mode" != timing ]] || [[ "$#" -gt 2 ]] || [[ "$mode" == test && "$#" -gt 1 ]]; then
    echo 'Usage: check-shape-context.sh [test|timing [5...20 passes]]' >&2
    exit 64
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/aski87-shape-context.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/Sources/Aski" "$scratch/Sources/ShapeContextTiming" "$scratch/Tests/AskiTests"
cp "$root/Sources/Aski/Algorithms/ShapeContext.swift" "$scratch/Sources/Aski/"
cp "$root/Tests/AskiTests/ShapeContextFootprintTests.swift" "$scratch/Tests/AskiTests/"
cp "$root/Scripts/research/ShapeContextTiming.swift" "$scratch/Sources/ShapeContextTiming/"
# This isolated core probe supports Swift 6.2; the real Package.swift and its
# Swift 6.3+ requirement are never edited or lowered by this script.
cat > "$scratch/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "AskiGeometryProbe",
    targets: [
        .target(name: "Aski", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AskiTests", dependencies: ["Aski"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "ShapeContextTiming", dependencies: ["Aski"], swiftSettings: [.swiftLanguageMode(.v6)])
    ]
)
SWIFT
swift=(swift)
if command -v xcrun >/dev/null 2>&1; then swift=(xcrun swift); fi
"${swift[@]}" --version >&2
if [[ "$mode" == test ]]; then
    "${swift[@]}" test --package-path "$scratch" -c release -Xswiftc -warnings-as-errors
else
    echo 'Histogram diagnostic only; map setup included, allocation counts unavailable.' >&2
    "${swift[@]}" run --package-path "$scratch" -c release -Xswiftc -warnings-as-errors ShapeContextTiming "${2:-5}"
fi
