#!/usr/bin/env bash
set -euo pipefail

# Validate the DocC catalog with public symbol links. Local gates need only the
# validation archive; CI/release callers opt into the second Markdown-sidecar
# conversion with --emit-markdown.
emit_markdown=0

usage() {
    cat <<'USAGE'
Usage: Scripts/validate-docc.sh [--emit-markdown]

Options:
  --emit-markdown  Also emit Markdown sidecars and their manifest for artifacts.
  -h, --help       Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --emit-markdown)
            emit_markdown=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "validate-docc: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

rm -rf /tmp/aski-docc-symbols /tmp/aski-docc /tmp/aski-docc-markdown
mkdir -p /tmp/aski-docc-symbols

# Cache only a verified Aski graph. The key includes all Aski Swift sources,
# package configuration, and the selected Swift/Xcode SDK toolchain. Keeping
# the cache under .build also makes `swift package clean` discard it.
# DocC still reads the current catalog on every invocation, so documentation
# edits and unresolved symbol links never receive a cache bypass.
symbol_cache_dir=".build/aski-docc-symbols-cache"
symbol_cache_graph="${symbol_cache_dir}/Aski.symbols.json"
symbol_cache_key_file="${symbol_cache_dir}/Aski.symbols.key"
symbol_cache_key="$(
    {
        printf '%s\n' 'aski-docc-symbol-cache-v1'
        xcrun swift --version 2>&1
        xcrun --find swift
        xcrun --show-sdk-path
        xcrun --show-sdk-version
        for input in Package.swift Package.resolved; do
            if [ -f "${input}" ]; then
                shasum -a 256 "${input}"
            fi
        done
        find Sources/Aski -type f -name '*.swift' -print | LC_ALL=C sort | while IFS= read -r source; do
            shasum -a 256 "${source}"
        done
    } | shasum -a 256 | awk '{ print $1 }'
)"

if ! test -s "${symbol_cache_graph}" \
    || ! test -f "${symbol_cache_key_file}" \
    || [ "$(cat "${symbol_cache_key_file}")" != "${symbol_cache_key}" ]; then
    # Generate the Aski symbol graph via the supported SwiftPM interface.
    # Unlike `swift build --target Aski -Xswiftc -emit-symbol-graph`, this
    # regenerates the graph on every cache miss regardless of .build cache
    # state. The old build-based path only emitted a graph for files it
    # actually (re)compiled, so on a warm .build it emitted nothing — docc then
    # saw an empty symbol dir and failed every article symbol link as a phantom
    # unresolved reference (ASTSK-25: ~109 "errors" that vanished after
    # `swift package clean`).

    # dump-symbol-graph attempts *every* target and exits non-zero when it
    # cannot load the test module (AskiPackageTests) for extraction — even
    # though it still emits a valid graph for the Aski library. There is no
    # per-target filter, so we don't gate on its exit code; the assertion below
    # gates on the Aski graph actually being (re)emitted. Clear any stale graph
    # first so the assertion can't pass on a leftover file from a previous run.
    rm -rf .build/*/symbolgraph
    xcrun swift package dump-symbol-graph --minimum-access-level public || true

    # dump-symbol-graph writes one <Module>.symbols.json per target into
    # .build/<triple>/symbolgraph/. Extension members fold into their type
    # under the default --omit-extension-block-symbols, so the single module
    # graph resolves every link.
    aski_symbols="$(find .build -type f -path '*/symbolgraph/Aski.symbols.json' -print -quit)"
    test -n "${aski_symbols}" && test -s "${aski_symbols}" \
        || { echo "Aski.symbols.json missing/empty — symbol graph not emitted"; exit 1; }

    mkdir -p "${symbol_cache_dir}"
    cp "${aski_symbols}" "${symbol_cache_graph}.tmp"
    printf '%s\n' "${symbol_cache_key}" > "${symbol_cache_key_file}.tmp"
    mv "${symbol_cache_graph}.tmp" "${symbol_cache_graph}"
    mv "${symbol_cache_key_file}.tmp" "${symbol_cache_key_file}"
fi

# Copy just the current, nonempty Aski module graph into the directory DocC
# consumes. Extension members fold into their type under the default
# --omit-extension-block-symbols, so the single module graph resolves every link.
cp "${symbol_cache_graph}" /tmp/aski-docc-symbols/Aski.symbols.json

# This temporary archive exists only to validate the catalog. Static-hosting
# conversion affects the emitted archive layout, not parse or link validation.
xcrun docc convert Sources/Aski/Aski.docc \
    --additional-symbol-graph-dir /tmp/aski-docc-symbols \
    --fallback-display-name Aski \
    --fallback-bundle-identifier com.bigcactuslabs.aski \
    --fallback-default-module-kind Framework \
    --no-transform-for-static-hosting \
    --output-path /tmp/aski-docc \
    --warnings-as-errors

# Markdown sidecars are release/CI artifacts, not a local validation input.
# Keeping this conversion behind an explicit flag prevents every `just check`
# and repo-doctor pass from compiling the same catalog twice.
if [ "$emit_markdown" -eq 1 ]; then
    # The --enable-experimental-markdown-output flag and its manifest counterpart
    # landed in Swift 6.3 (swift-docc PR #1303 + #1415). Artifact callers require
    # output, so fail here rather than silently letting their later upload step
    # discover that the selected toolchain lacks the feature.
    if ! xcrun docc convert --help 2>/dev/null | grep -q -- "--enable-experimental-markdown-output"; then
        echo "Markdown output was requested, but this DocC toolchain does not expose --enable-experimental-markdown-output" >&2
        exit 1
    fi

    xcrun docc convert Sources/Aski/Aski.docc \
        --additional-symbol-graph-dir /tmp/aski-docc-symbols \
        --fallback-display-name Aski \
        --fallback-bundle-identifier com.bigcactuslabs.aski \
        --fallback-default-module-kind Framework \
        --output-path /tmp/aski-docc-markdown \
        --enable-experimental-markdown-output \
        --enable-experimental-markdown-output-manifest
fi
