#!/bin/bash
# ASKI-75 untimed diagnostic passes (separate scratch paths, never mixed with timed samples):
# a --very-verbose debug build with a linker map, and a release build, for one arm.
# usage: footprint-passes.sh <package-dir> <arm-label> <out-dir>
set -euo pipefail
pkg="$(cd "$1" && pwd -P)"; arm="$2"; out="$3"
mkdir -p "$out"; cd "$pkg"
dbg="$pkg/.build/aski75-map"; rel="$pkg/.build/aski75-release"
for s in "$dbg" "$rel"; do [ ! -e "$s" ] || { echo "$s exists" >&2; exit 2; }; done
common=(--package-path "$pkg" --build-system swiftbuild --force-resolved-versions --product aski)
xcrun swift package --package-path "$pkg" --scratch-path "$dbg" resolve > /dev/null 2>&1
xcrun swift build "${common[@]}" --scratch-path "$dbg" --very-verbose \
    -Xlinker -map -Xlinker "$out/$arm-debug.map" > "$out/$arm-debug-vv.log" 2>&1
cp "$(xcrun swift build "${common[@]}" --scratch-path "$dbg" --show-bin-path)/aski" "$out/$arm-debug-map-aski"
xcrun swift package --package-path "$pkg" --scratch-path "$rel" resolve > /dev/null 2>&1
/usr/bin/time -lp -o "$out/$arm-release.time" xcrun swift build "${common[@]}" --scratch-path "$rel" -c release > "$out/$arm-release.log" 2>&1
cp "$(xcrun swift build "${common[@]}" --scratch-path "$rel" -c release --show-bin-path)/aski" "$out/$arm-release-aski"
