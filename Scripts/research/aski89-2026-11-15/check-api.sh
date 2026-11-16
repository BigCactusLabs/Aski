#!/bin/bash
set -eu

probe="$(cd "$(dirname "$0")" && pwd)/TemporaryBufferProbe.swift"

check_compiler() (
    if [[ "$1" == native ]]; then
        unset TOOLCHAINS
    else
        export TOOLCHAINS="$1"
    fi
    local version sdk triple
    version="$(xcrun swift --version)"
    printf '%s\n' "$version"
    case "$1:$version" in
        native:*"Swift version 6.4"*|org.swift.631202604131a:*"Swift version 6.3.1"*) ;;
        *) printf 'Unexpected compiler for %s\n' "$1" >&2; return 1 ;;
    esac
    while read -r sdk triple; do
        printf '%s %s\n' "$sdk" "$triple"
        xcrun --sdk "$sdk" swiftc -typecheck -swift-version 6 -warnings-as-errors \
            -target "$triple" -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" "$probe"
    done <<'TARGETS'
macosx arm64-apple-macosx15.0
iphonesimulator arm64-apple-ios18.0-simulator
xrsimulator arm64-apple-xros2.0-simulator
TARGETS
)

check_compiler org.swift.631202604131a
check_compiler native
