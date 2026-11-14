#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* || -e "$1" ]]; then
    echo "Usage: capture.sh <new-absolute-output-directory>" >&2
    exit 64
fi

output="$1"
instrument_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(git -C "$instrument_dir" rev-parse --show-toplevel)"
instrument="${instrument_dir#"$root/"}"
source_commit="$(git -C "$root" rev-parse HEAD)"
if ! git -C "$root" cat-file -e "$source_commit:$instrument/PROTOCOL.md" ||
    [[ -n "$(git -C "$root" status --porcelain -- "$instrument")" ]]; then
    echo "Capture requires a committed protocol and instrument." >&2
    exit 65
fi

scratch="$(mktemp -d /private/tmp/aski108-capture.XXXXXXXX)"
mkdir -p "$scratch/Aski" "$scratch/Inspection/Sources/Inspect" "$output"
git -C "$root" archive "$source_commit" | tar -xf - -C "$scratch/Aski"
archived="$scratch/Aski/$instrument"
project="$scratch/Inspection"
cp "$archived/Inspect.swift" "$project/Sources/Inspect/Inspect.swift"
cp "$scratch/Aski/Package.resolved" "$project/Package.resolved"
cat > "$project/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Inspection",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../Aski")],
    targets: [.executableTarget(name: "Inspect", dependencies: [.product(name: "Aski", package: "Aski")])]
)
MANIFEST

fixtures="$scratch/Aski/docs/Research/Corpus/nasa-occupancy-v1/assets"
build=(xcrun swift build --package-path "$project" --scratch-path "$scratch/build" -c release --product Inspect)
run=("$scratch/build/release/Inspect" "$fixtures" "$output")
{
    printf 'source_commit=%s\nsource_snapshot=git_archive\nsource_dirty=false\n' "$source_commit"
    printf 'wrapper_argv='
    printf ' %q' "${BASH_SOURCE[0]}" "$@"
    printf '\nbuild_argv='
    printf ' %q' "${build[@]}"
    printf '\nrun_argv='
    printf ' %q' "${run[@]}"
    printf '\n'
    date -u '+capture_started=%Y-%m-%dT%H:%M:%SZ'
    sw_vers
    uname -m
    printf 'DEVELOPER_DIR=%s\n' "${DEVELOPER_DIR:-}"
    xcode-select -p
    xcrun xcodebuild -version
    xcrun swift --version
    (
        cd "$scratch/Aski"
        shasum -a 256 Package.swift Package.resolved "$instrument/"{Inspect.swift,capture.sh,PROTOCOL.md}
        cd "$fixtures"
        shasum -a 256 rcs-function-diagram.jpg spacecraft-attitude-diagram.jpg james-lovell-portrait.jpg
    )
    printf 'temporary_manifest_sha256='
    shasum -a 256 "$project/Package.swift" | awk '{print $1}'
} > "$output/provenance.txt"

"${build[@]}" > "$output/build.log" 2>&1
(
    cd "$project"
    shasum -a 256 Package.resolved
) >> "$output/provenance.txt"
"${run[@]}" 2>&1 | tee "$output/inspection.txt"
(
    cd "$output"
    shasum -a 256 -- *.csv *.png *.jpg *.txt *.log > SHA256SUMS
)
