#!/bin/bash
# ASKI-75 build sample: one clean, one warm (no-op) and one link-only rebuild of
# `swift build --product aski` in a fresh scratch path, Swift Build backend pinned.
# usage: sample.sh <package-dir> <arm-label> <sample-id> <out-dir>
# Writes <out-dir>/<sample-id>-<arm>-{resolve,clean,warm,link}.{log,time} and appends
# one row per timed step to <out-dir>/samples.tsv.
set -euo pipefail
pkg="$(cd "$1" && pwd -P)"; arm="$2"; id="$3"; out="$4"
scratch="$pkg/.build/aski75-$id"
[ ! -e "$scratch" ] || { echo "scratch path $scratch already exists" >&2; exit 2; }
mkdir -p "$out"
cd "$pkg"
base=(xcrun swift build --package-path "$pkg" --scratch-path "$scratch"
    --build-system swiftbuild --force-resolved-versions --product aski)
# Dependency checkouts come from the shared SwiftPM cache; resolve before any timing.
xcrun swift package --package-path "$pkg" --scratch-path "$scratch" resolve > "$out/$id-$arm-resolve.log" 2>&1
step() {
    local name="$1" load
    load="$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')"
    local status=0
    /usr/bin/time -lp -o "$out/$id-$arm-$name.time" "${base[@]}" > "$out/$id-$arm-$name.log" 2>&1 || status=$?
    local real rss
    real="$(awk '$1=="real"{print $2}' "$out/$id-$arm-$name.time")"
    rss="$(awk '/maximum resident set size/{print $1}' "$out/$id-$arm-$name.time")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$arm" "$name" "$real" "$rss" "$load" "$status" >> "$out/samples.tsv"
    [ "$status" -eq 0 ] || { echo "$name build failed ($status)" >&2; exit 1; }
}
step clean
step warm
bin="$("${base[@]}" --show-bin-path)"
rm "$bin/aski"
step link
[ -x "$bin/aski" ] || { echo "link step did not recreate aski" >&2; exit 1; }
printf '%s\t%s\t%s\t%s\n' "$id" "$arm" "$(stat -f %z "$bin/aski")" "$(shasum -a 256 "$bin/aski" | cut -c1-64)" >> "$out/binaries.tsv"
