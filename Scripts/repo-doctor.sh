#!/usr/bin/env bash
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
WORKFLOW_DIR="$ROOT/.github/workflows"
# The Swift minimum comes from the manifest's swift-tools-version; no Xcode version is pinned.
ASKI_REQUIRED_SWIFT_VERSION="${ASKI_REQUIRED_SWIFT_VERSION:-$(sed -n 's|^// swift-tools-version: *\([0-9][0-9]*\.[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*|\1|p' "$ROOT/Package.swift" 2>/dev/null | head -n 1)}"
DEFAULT_CHECKS=(toolchain package-resolved swift-format research-index repo-map docc metallib workflow-refs dirty)
SELECTED_CHECKS=()
SKIPPED_CHECKS=()
FAILURES=()

usage() {
    cat <<'USAGE'
Usage: Scripts/repo-doctor.sh [options]

Options:
  --check NAME          Run only NAME. Can be repeated.
  --skip NAME           Skip NAME from the default check set. Can be repeated.
  --workflow-dir PATH   Override the workflow directory for workflow-refs.
  -h, --help            Show this help.

Checks:
  toolchain package-resolved swift-format research-index repo-map docc metallib workflow-refs dirty
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check)
            [ "$#" -ge 2 ] || { echo "repo-doctor: --check requires a name" >&2; exit 64; }
            SELECTED_CHECKS+=("$2")
            shift 2
            ;;
        --skip)
            [ "$#" -ge 2 ] || { echo "repo-doctor: --skip requires a name" >&2; exit 64; }
            SKIPPED_CHECKS+=("$2")
            shift 2
            ;;
        --workflow-dir)
            [ "$#" -ge 2 ] || { echo "repo-doctor: --workflow-dir requires a path" >&2; exit 64; }
            WORKFLOW_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "repo-doctor: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

# Validate both lists before any expensive or mutating check runs. A misspelled
# --skip must not silently turn a requested partial check into a full preflight.
for name in "${SELECTED_CHECKS[@]}" "${SKIPPED_CHECKS[@]}"; do
    case "$name" in
        toolchain|package-resolved|swift-format|research-index|repo-map|docc|metallib|workflow-refs|dirty) ;;
        *) echo "repo-doctor: unknown check '$name'" >&2; exit 64 ;;
    esac
done

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/aski-doctor.XXXXXX")" || exit 1
METALLIB_BACKUP=""
METALLIB_PATH=""
METALLIB_LOCK=""

restore_metallib() {
    if [ -n "$METALLIB_BACKUP" ]; then
        if ! cp "$METALLIB_BACKUP" "$METALLIB_PATH"; then
            echo "repo-doctor: could not restore metallib; backup retained at $METALLIB_BACKUP" >&2
            return 1
        fi
        METALLIB_BACKUP=""
    fi
    if [ -n "$METALLIB_LOCK" ]; then
        rmdir "$METALLIB_LOCK" || return 1
        METALLIB_LOCK=""
    fi
}

cleanup() {
    local status=$?
    trap - EXIT
    if restore_metallib; then
        rm -rf "$SCRATCH"
    else
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [ "${#SELECTED_CHECKS[@]}" -gt 0 ]; then
    CHECKS=("${SELECTED_CHECKS[@]}")
else
    CHECKS=("${DEFAULT_CHECKS[@]}")
fi

is_skipped() {
    local needle="$1"
    local skipped
    for skipped in "${SKIPPED_CHECKS[@]}"; do
        [ "$skipped" = "$needle" ] && return 0
    done
    return 1
}

record_failure() {
    FAILURES+=("$1")
    printf 'FAIL %s\n' "$1"
}

record_pass() {
    printf 'PASS %s\n' "$1"
}

# Compares MAJOR.MINOR[.PATCH] against ASKI_REQUIRED_SWIFT_VERSION; a missing patch counts as 0.
version_ge() {
    local actual_major="$1"
    local actual_minor="$2"
    local actual_patch="${3:-0}"
    local required_major required_minor required_patch
    IFS=. read -r required_major required_minor required_patch <<<"$ASKI_REQUIRED_SWIFT_VERSION"
    required_patch="${required_patch:-0}"

    [ "$actual_major" -ne "$required_major" ] && { [ "$actual_major" -gt "$required_major" ]; return; }
    [ "$actual_minor" -ne "$required_minor" ] && { [ "$actual_minor" -gt "$required_minor" ]; return; }
    [ "$actual_patch" -ge "$required_patch" ]
}

check_toolchain() {
    local xcode_output xcode_line swift_output swift_line swift_version major minor patch
    xcode_output="$(xcodebuild -version 2>&1)" || {
        record_failure "xcodebuild is not available"
        return
    }
    xcode_line="$(printf '%s\n' "$xcode_output" | head -n 1)"
    printf 'INFO toolchain %s\n' "$xcode_line"

    if [[ ! "$ASKI_REQUIRED_SWIFT_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        record_failure "could not read the Swift minimum from swift-tools-version in Package.swift"
        return
    fi

    swift_output="$(xcrun swift --version 2>&1)" || {
        record_failure "xcrun swift toolchain not available"
        return
    }
    swift_line="$(printf '%s\n' "$swift_output" | head -n 1)"
    if [[ "$swift_line" =~ Swift[[:space:]]version[[:space:]](([0-9]+)\.([0-9]+)(\.[0-9]+)?) ]]; then
        swift_version="${BASH_REMATCH[1]}"
        major="${BASH_REMATCH[2]}"
        minor="${BASH_REMATCH[3]}"
        patch="${BASH_REMATCH[4]#.}"
        if version_ge "$major" "$minor" "$patch"; then
            record_pass "toolchain Swift $swift_version >= $ASKI_REQUIRED_SWIFT_VERSION"
        else
            record_failure "toolchain Swift $swift_version is older than required $ASKI_REQUIRED_SWIFT_VERSION"
        fi
    else
        record_failure "could not parse Swift version from: $swift_line"
    fi
}

check_swift_format() {
    local log
    log="$SCRATCH/swift-format.log"
    if (cd "$ROOT" && ./Scripts/swift-format-check.sh) >"$log" 2>&1; then
        rm -f "$log"
        record_pass "swift-format full-tree lint passes"
    else
        record_failure "swift-format full-tree lint failed; rerun: ./Scripts/swift-format-check.sh"
        tail -40 "$log" >&2
        rm -f "$log"
    fi
}

check_package_resolved() {
    if [ ! -f "$ROOT/Package.resolved" ]; then
        record_failure "Package.resolved is missing; run xcrun swift package resolve"
        return
    fi
    (
        cd "$ROOT" || exit 1
        xcrun swift package resolve
    ) >"$SCRATCH/package-resolve.log" 2>&1
    local status=$?
    if [ "$status" -ne 0 ]; then
        record_failure "xcrun swift package resolve failed"
        tail -40 "$SCRATCH/package-resolve.log" >&2
        rm -f "$SCRATCH/package-resolve.log"
        return
    fi
    rm -f "$SCRATCH/package-resolve.log"

    if git -C "$ROOT" diff --quiet HEAD -- Package.resolved; then
        record_pass "Package.resolved is consistent"
    else
        record_failure "Package.resolved changed after swift package resolve; commit the lockfile update"
    fi
}

check_research_index() {
    local log
    log="$SCRATCH/research-index.log"
    if (cd "$ROOT" && xcrun swift run BuildResearchIndex --check) >"$log" 2>&1; then
        rm -f "$log"
        record_pass "research index is current"
    else
        record_failure "research index failed; rerun: xcrun swift run BuildResearchIndex --check"
        tail -40 "$log" >&2
        rm -f "$log"
    fi
}

check_repo_map() {
    local log
    log="$SCRATCH/repo-map.log"
    if (cd "$ROOT" && xcrun swift run BuildRepoMap --check) >"$log" 2>&1; then
        rm -f "$log"
        record_pass "repo map is current"
    else
        record_failure "repo map is out of date; rerun: just regen-repo-map (then commit docs/repo-map.generated.md)"
        tail -40 "$log" >&2
        rm -f "$log"
    fi
}

check_docc() {
    local log
    log="$SCRATCH/docc.log"
    if (cd "$ROOT" && ./Scripts/validate-docc.sh) >"$log" 2>&1; then
        rm -f "$log"
        record_pass "DocC validation passes"
    else
        record_failure "DocC validation failed; rerun: ./Scripts/validate-docc.sh"
        tail -40 "$log" >&2
        rm -f "$log"
    fi
}

check_metallib() {
    local metallib before status metal_path metallib_path
    metallib="$ROOT/Sources/Aski/Resources/Kernels/default.metallib"
    before="$SCRATCH/default.metallib"
    if [ ! -f "$metallib" ]; then
        rm -f "$before"
        record_failure "checked-in metallib is missing: $metallib"
        return
    fi
    if ! metal_path="$(TOOLCHAINS=com.apple.dt.toolchain.Metal xcrun --find metal 2>&1)"; then
        rm -f "$before"
        record_failure "xcrun --find metal failed under TOOLCHAINS=com.apple.dt.toolchain.Metal; run xcodebuild -downloadComponent MetalToolchain for the selected Xcode"
        printf '%s\n' "$metal_path" >&2
        return
    fi
    if ! metallib_path="$(TOOLCHAINS=com.apple.dt.toolchain.Metal xcrun --find metallib 2>&1)"; then
        rm -f "$before"
        record_failure "xcrun --find metallib failed under TOOLCHAINS=com.apple.dt.toolchain.Metal; run xcodebuild -downloadComponent MetalToolchain for the selected Xcode"
        printf '%s\n' "$metallib_path" >&2
        return
    fi
    printf 'INFO metal: %s\n' "$metal_path"
    printf 'INFO metallib: %s\n' "$metallib_path"

    mkdir -p "$ROOT/.build" || { record_failure "cannot create .build"; return; }
    if ! mkdir "$ROOT/.build/aski-metallib-check.lock" 2>/dev/null; then
        record_failure "metallib check is already running; if interrupted, verify no check is active before removing .build/aski-metallib-check.lock"
        return
    fi
    METALLIB_LOCK="$ROOT/.build/aski-metallib-check.lock"
    if ! cp "$metallib" "$before"; then
        record_failure "cannot back up the checked-in metallib"
        restore_metallib || record_failure "cannot release the metallib check lock"
        return
    fi
    METALLIB_BACKUP="$before"
    METALLIB_PATH="$metallib"
    (
        cd "$ROOT" || exit 1
        xcrun swift run BuildKernelLibrary
    ) >"$SCRATCH/kernel-regen.log" 2>&1
    status=$?
    if [ "$status" -ne 0 ]; then
        restore_metallib || { record_failure "metallib restoration failed"; return; }
        record_failure "BuildKernelLibrary failed"
        tail -40 "$SCRATCH/kernel-regen.log" >&2
        rm -f "$before" "$SCRATCH/kernel-regen.log"
        return
    fi
    rm -f "$SCRATCH/kernel-regen.log"

    if cmp -s "$before" "$metallib"; then
        restore_metallib || { record_failure "metallib restoration failed"; return; }
        rm -f "$before"
        record_pass "metallib matches regenerated output"
    else
        restore_metallib || { record_failure "metallib restoration failed"; return; }
        rm -f "$before"
        local xcode_version
        xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
        record_failure "default.metallib differs from regenerated output under ${xcode_version:-the selected Xcode}; run just regen-kernels with the intended release toolchain and commit it"
    fi
}

trim_uses_value() {
    local value="$1"
    value="${value#*uses:}"
    value="${value%%#*}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s' "$value"
}

check_workflow_refs() {
    local file line number content value ref found
    found=0
    if [ ! -d "$WORKFLOW_DIR" ]; then
        record_pass "workflow refs skipped; no workflow directory at $WORKFLOW_DIR"
        return
    fi

    while IFS= read -r line; do
        file="${line%%:*}"
        line="${line#*:}"
        number="${line%%:*}"
        content="${line#*:}"
        value="$(trim_uses_value "$content")"

        [ -z "$value" ] && continue
        [[ "$value" == ./* ]] && continue
        [[ "$value" == docker://* ]] && continue

        if [[ "$value" == *@* ]]; then
            ref="${value##*@}"
            if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
                continue
            fi
            found=1
            record_failure "$file:$number uses $value; pin remote actions to a full-length commit SHA"
        else
            found=1
            record_failure "$file:$number uses $value; remote actions must include @full-length commit SHA"
        fi
    done < <(grep -RnE '^[[:space:]-]*uses:[[:space:]]*' "$WORKFLOW_DIR" 2>/dev/null || true)

    if [ "$found" -eq 0 ]; then
        record_pass "workflow refs are pinned to full-length commit SHAs"
    fi
}

check_dirty() {
    local status
    if ! status="$(git -C "$ROOT" status --porcelain --untracked-files=all 2>&1)"; then
        record_failure "cannot read git worktree status"
        printf '%s\n' "$status" >&2
        return
    fi
    if [ -z "$status" ]; then
        record_pass "git worktree is clean"
    else
        record_failure "git worktree is dirty; commit, stash, or remove local changes before release"
        printf '%s\n' "$status" >&2
    fi
}

run_check() {
    local check="$1"
    is_skipped "$check" && {
        printf 'SKIP %s\n' "$check"
        return
    }

    case "$check" in
        toolchain) check_toolchain ;;
        package-resolved) check_package_resolved ;;
        swift-format) check_swift_format ;;
        research-index) check_research_index ;;
        repo-map) check_repo_map ;;
        docc) check_docc ;;
        metallib) check_metallib ;;
        workflow-refs) check_workflow_refs ;;
        dirty) check_dirty ;;
        *)
            record_failure "unknown check '$check'"
            ;;
    esac
}

for check in "${CHECKS[@]}"; do
    run_check "$check"
done

if [ "${#FAILURES[@]}" -gt 0 ]; then
    printf '\nrepo doctor: %d failure(s)\n' "${#FAILURES[@]}" >&2
    exit 1
fi

printf '\nrepo doctor: OK\n'
