#!/usr/bin/env bash
set -euo pipefail
# An exported CDPATH would redirect the cd-based path resolution below.
unset CDPATH

usage() {
    cat <<'USAGE'
Usage: Scripts/package-cli.sh --output-dir NEW_DIRECTORY

Build a macOS CLI release candidate from the clean, committed checkout.
The output directory must not exist; its parent must already exist.
It receives an archive and SHA256SUMS only after an extracted render smoke check.

Requires macOS, full Xcode with the package's Swift toolchain, and Git.
Run the repository's normal release gates separately on the same commit.
This command does not sign, notarize, tag, upload, or install the candidate.
USAGE
}

die() { printf 'package-cli: %s\n' "$*" >&2; exit 1; }
output_arg=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir)
            if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" = -* ]] || [ -n "$output_arg" ]; then
                printf 'package-cli: supply --output-dir once with a path\n' >&2
                exit 64
            fi
            output_arg="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'package-cli: unknown argument: %s\n' "$1" >&2; exit 64 ;;
    esac
done
[ -n "$output_arg" ] || { usage >&2; exit 64; }
output_parent="$(cd "$(dirname "$output_arg")" && pwd -P)" || die "output parent must exist"
output_leaf="$(basename "$output_arg")"
case "$output_leaf" in .|..|/) die "output must name a new directory" ;; esac
output_dir="$output_parent/$output_leaf"
[ ! -e "$output_dir" ] && [ ! -L "$output_dir" ] || die "output already exists: $output_dir"
[ "$(uname -s)" = Darwin ] || die "packaging requires macOS and full Xcode"
for command_name in git xcrun xcodebuild sw_vers sips plutil shasum tar cmp diff find od tr awk mktemp; do
    command -v "$command_name" >/dev/null || die "required command is unavailable: $command_name"
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[ "$(git -C "$repo_root" rev-parse --show-toplevel)" = "$repo_root" ] || die "run from an Aski checkout"
case "$output_dir" in
    "$repo_root"/*)
        git -C "$repo_root" check-ignore --quiet -- "${output_dir#"$repo_root"/}/" ||
            die "use an output directory outside the checkout or under an ignored directory"
        ;;
esac
require_clean() {
    local state
    state="$(git -C "$repo_root" status --porcelain --untracked-files=all)" || die "cannot inspect worktree"
    [ -z "$state" ] || die "commit or remove tracked and untracked changes before packaging"
}
require_clean
source_commit="$(git -C "$repo_root" rev-parse --verify HEAD)"
xcode_version="$(xcodebuild -version)" || die "select a full Xcode installation"
swift_version="$(xcrun swift --version)" || die "selected Xcode has no Swift toolchain"
build_os="$(sw_vers -productVersion)"

work_root="$(mktemp -d "${TMPDIR:-/tmp}/aski-package.XXXXXX")"
work_root="$(cd "$work_root" && pwd -P)"
build_pid=""
owned_output=""
stop_build() {
    if [ -n "$build_pid" ]; then
        kill -TERM -- "-$build_pid" 2>/dev/null || true
        local attempt
        for attempt in 1 2 3 4 5; do
            kill -0 -- "-$build_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL -- "-$build_pid" 2>/dev/null || true
        wait "$build_pid" 2>/dev/null || true
        build_pid=""
    fi
}
cleanup() {
    local status=$?
    trap - EXIT
    stop_build
    [ -z "$owned_output" ] || rm -rf "$owned_output"
    rm -rf "$work_root"
    exit "$status"
}
interrupt() { trap '' INT TERM HUP; stop_build; exit "$1"; }
trap cleanup EXIT
trap 'interrupt 130' INT
trap 'interrupt 143' TERM
trap 'interrupt 129' HUP

# Build the captured commit, not mutable working-tree files. The private scratch
# path is deleted before smoke testing, eliminating SwiftPM's absolute fallback.
# https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift
mkdir -p "$work_root/source" "$work_root/stage" "$work_root/output" "$work_root/unpacked" "$work_root/smoke"
git -C "$repo_root" archive "$source_commit" | tar -xf - -C "$work_root/source"
source_root="$work_root/source"
[ -s "$source_root/Package.resolved" ] || die "Package.resolved is required"
cp "$source_root/docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg" "$work_root/smoke/input.jpg"

# Both calls use the same native backend, lockfile, configuration and scratch path.
# --force-resolved-versions: https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftBuild.md
build_args=(swift build --package-path "$source_root" --scratch-path "$work_root/build"
    --build-system native --force-resolved-versions -c release --product aski)
printf 'package-cli: building committed source %s\n' "$source_commit" >&2
set -m
xcrun "${build_args[@]}" >&2 &
build_pid=$!
set +m
if wait "$build_pid"; then build_pid=""; else die "release build failed"; fi
bin_dir="$(xcrun "${build_args[@]}" --show-bin-path)"
bin_dir="$(cd "$bin_dir" && pwd -P)" || die "build did not produce a binary directory"
case "$bin_dir" in "$work_root/build"/*) ;; *) die "binary directory escaped the private build" ;; esac
[ -x "$bin_dir/aski" ] || die "aski executable is missing"
[ -d "$bin_dir/Aski_Aski.bundle" ] && [ ! -L "$bin_dir/Aski_Aski.bundle" ] || die "Aski_Aski.bundle is missing"
architecture="$(xcrun lipo -archs "$bin_dir/aski")"
case "$architecture" in arm64|x86_64) ;; *) die "expected one supported architecture, got: $architecture" ;; esac
stem="aski-${source_commit:0:12}-macos-$architecture"
package_dir="$work_root/stage/$stem"
mkdir "$package_dir"
cp "$bin_dir/aski" "$package_dir/aski"
cp -R "$bin_dir/Aski_Aski.bundle" "$package_dir/Aski_Aski.bundle"
cp "$source_root/LICENSE" "$source_root/NOTICE" "$package_dir/"
cp "$source_root/Sources/Aski/Resources/Fonts/OFL.txt" "$package_dir/OFL.txt"

# Copy-rule resources must remain complete and byte-identical. A successful render
# alone cannot prove this: the bundled font and Metal effects have fallback paths.
bundle="$package_dir/Aski_Aski.bundle"
bundle_links="$(find "$bundle" -type l -print)" || die "cannot inspect bundle links"
[ -z "$bundle_links" ] || die "resource bundle must not contain symlinks"
for resource_dir in Fonts ShapeData Kernels; do
    diff -qr "$source_root/Sources/Aski/Resources/$resource_dir" "$bundle/$resource_dir" >&2 ||
        die "incomplete or changed $resource_dir resources"
done
for charset in standard minimal blocks dots lines diagonal cross diamond mixed braille; do
    [ -s "$bundle/ShapeData/$charset.bin" ] || die "missing character set: $charset"
done
for resource in Fonts/CourierPrime-Regular.ttf Fonts/OFL.txt Kernels/default.metallib PrivacyInfo.xcprivacy; do
    [ -s "$bundle/$resource" ] || die "missing resource: $resource"
done
cmp -s "$source_root/Sources/Aski/PrivacyInfo.xcprivacy" "$bundle/PrivacyInfo.xcprivacy" || die "privacy manifest changed"
cat > "$package_dir/release-info.txt" <<INFO
Aski CLI release candidate
source-commit: $source_commit
architecture: $architecture
build-macos: $build_os
configuration: release
build-system: native
dependencies: Package.resolved (--force-resolved-versions)
signing: no distribution signing or notarization performed
version-note: CLI --version probes the working directory; source-commit identifies this archive.

$swift_version
$xcode_version
INFO
archive="$work_root/output/$stem.tar.gz"
# Omit the builder's account name and macOS extended attributes (e.g. provenance).
COPYFILE_DISABLE=1 tar --no-xattrs --numeric-owner -czf "$archive" -C "$work_root/stage" "$stem"

# The binary cannot fall back to its compiled-in resource path after this removal.
# SwiftPM also tests executables moved together with their resource-bundle siblings:
# https://github.com/swiftlang/swift-package-manager/blob/main/Tests/FunctionalTests/ResourcesTests.swift
rm -rf "$work_root/build" "$work_root/source" "$work_root/stage"
tar -xzf "$archive" -C "$work_root/unpacked"
smoke_cli="$work_root/unpacked/$stem/aski"
(
    cd "$work_root/smoke"
    "$smoke_cli" --help > help.txt
    "$smoke_cli" render input.jpg --columns 40 --output result.txt --render-png result.png --width 160 >&2
    "$smoke_cli" inspect input.jpg --columns 40 --format json --output inspection.json >&2
    [ -s help.txt ] && [ -s result.txt ] && [ -s result.png ] && [ -s inspection.json ] || die "smoke output is missing"
    awk '/[^[:space:]]/ { found=1 } END { exit !found }' result.txt || die "smoke text contains no glyphs"
    [ "$(od -An -tx1 -N8 result.png | tr -d '[:space:]')" = 89504e470d0a1a0a ] || die "smoke output is not PNG"
    dimensions="$(sips -g pixelWidth -g pixelHeight result.png)"
    [ "$(printf '%s\n' "$dimensions" | awk '$1 == "pixelWidth:" { print $2 }')" = 160 ] || die "smoke PNG width is not 160"
    height="$(printf '%s\n' "$dimensions" | awk '$1 == "pixelHeight:" { print $2 }')"
    [[ "$height" =~ ^[1-9][0-9]*$ ]] || die "smoke PNG has invalid height"
    first_token="$(awk 'match($0, /[^[:space:]]/) { print substr($0, RSTART, 1); exit }' inspection.json)"
    [ "$first_token" = '{' ] || die "inspection output is not a JSON object"
    # plutil -lint rejects JSON on macOS; -convert parses JSON and plists alike.
    plutil -convert xml1 -o /dev/null -- inspection.json || die "inspection JSON is invalid"
    schema_version="$(plutil -extract schemaVersion raw -expect integer -o - -- inspection.json)" || die "missing inspection schema"
    [ "$schema_version" = 1 ] || die "unexpected inspection schema"
    inspection_columns="$(plutil -extract conversion.columns raw -expect integer -o - -- inspection.json)" || die "missing inspection columns"
    [ "$inspection_columns" = 40 ] || die "unexpected inspection columns"
)
require_clean
[ "$(git -C "$repo_root" rev-parse --verify HEAD)" = "$source_commit" ] || die "HEAD changed during packaging"
(
    cd "$work_root/output"
    shasum -a 256 "$stem.tar.gz" > SHA256SUMS
)
# mkdir reserves the new destination without replacing a concurrent creation.
mkdir "$output_dir" || die "could not create the new output directory"
owned_output="$output_dir"
cp "$archive" "$work_root/output/SHA256SUMS" "$output_dir/"
owned_output=""
printf '%s\n' "$output_dir/$stem.tar.gz" "$output_dir/SHA256SUMS"
