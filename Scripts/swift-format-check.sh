#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

usage() {
    cat <<'USAGE'
Usage: Scripts/swift-format-check.sh

Lints Package.swift, Sources, Tools, Benchmarks, and Tests with .swift-format.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "swift-format-check: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if ! command -v swift-format >/dev/null 2>&1 && ! xcrun swift format --version >/dev/null 2>&1; then
    echo "swift-format-check: swift-format is not available in the selected Swift toolchain" >&2
    exit 1
fi

CONFIG="$ROOT/.swift-format"
if [ ! -f "$CONFIG" ]; then
    echo "swift-format-check: missing $CONFIG" >&2
    exit 1
fi

run_lint() {
    if command -v swift-format >/dev/null 2>&1; then
        swift-format lint --configuration "$CONFIG" --strict "$@"
    else
        xcrun swift format lint --configuration "$CONFIG" --strict "$@"
    fi
}

paths=(Package.swift Sources Tools Benchmarks Tests)
(cd "$ROOT" && run_lint --recursive "${paths[@]}")
