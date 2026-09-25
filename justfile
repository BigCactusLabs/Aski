set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

check:
    ./Scripts/swift-format-check.sh
    xcrun swift build --build-tests
    ASKI_SKIP_BUILD=1 just lifecycle-check
    ASKI_SKIP_BUILD=1 just repo-map-check
    ASKI_SKIP_BUILD=1 ASKI_SKIP_REGISTRY_TESTS=1 ASKI_SKIP_MEDIA_TESTS=1 just test-without-video-deadlock
    ASKI_SKIP_BUILD=1 ASKI_SERIAL_MEDIA=1 just test-media
    ASKI_SKIP_BUILD=1 just test-video-deadlock
    ./Scripts/validate-docc.sh

# Fast inner-loop gate: format + filtered tests + structural checks.
# Skips the full executable build, the full `swift test` suite, and DocC.
# Run `just check` before committing.
check-fast:
    ./Scripts/swift-format-check.sh
    just test-fast
    ASKI_SKIP_BUILD=1 just lifecycle-check
    ASKI_SKIP_BUILD=1 just repo-map-check

format-check *args:
    ./Scripts/swift-format-check.sh {{ args }}

test:
    xcrun swift test

test-without-video-deadlock:
    if [[ -n "${ASKI_SKIP_BUILD:-}" && -n "${ASKI_SKIP_REGISTRY_TESTS:-}" && -n "${ASKI_SKIP_MEDIA_TESTS:-}" ]]; then xcrun swift test --skip-build --skip 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock|everyNoteHasValidFrontMatter|generatedArtifactsAreInSync|everyCorpusAndResultHasValidManifest|generatedMapIsInSync|GIF|Video|MotionLab'; elif [[ -n "${ASKI_SKIP_BUILD:-}" && -n "${ASKI_SKIP_REGISTRY_TESTS:-}" ]]; then xcrun swift test --skip-build --skip 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock|everyNoteHasValidFrontMatter|generatedArtifactsAreInSync|everyCorpusAndResultHasValidManifest|generatedMapIsInSync'; elif [[ -n "${ASKI_SKIP_BUILD:-}" ]]; then xcrun swift test --skip-build --skip 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'; else xcrun swift test --skip 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'; fi

test-video-deadlock:
    if [[ -n "${ASKI_SKIP_BUILD:-}" ]]; then xcrun swift test --skip-build --no-parallel --filter 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'; else xcrun swift test --no-parallel --filter 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'; fi

test-fast:
    xcrun swift test --skip 'Snapshot|GIF|Video|MotionLab|AccessLab|DecolorLab|ColorLab|Research|RepoMap|DocumentationLinkTests|CommandSurfaceTests|CommandSurfaceGoldenTests|KnobDocumentationTests|Metallib|Artifact'

test-snapshots:
    xcrun swift test --filter 'SnapshotTests|BuiltInPaletteSnapshotTests|MaskSnapshotTests|TileGridRenderingSnapshotTests|CompositionSnapshotTests|EffectKernelSnapshotTests'

test-media:
    if [[ -n "${ASKI_SERIAL_MEDIA:-}" && -n "${ASKI_SKIP_BUILD:-}" ]]; then xcrun swift test --skip-build --no-parallel --filter 'GIF|Video|MotionLab' --skip 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'; elif [[ -n "${ASKI_SERIAL_MEDIA:-}" ]]; then xcrun swift test --no-parallel --filter 'GIF|Video|MotionLab' --skip 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'; else xcrun swift test --filter 'AskiGIF|AskiVideo|AskiMotionLab|AskiResampleGIF|AskiResampleVideo|GIF89aFixture'; fi

test-research:
    xcrun swift test --filter 'Research|Manifest|AskiColorLab|AskiAccessLab|AskiDecolorLab|AskiMotionLab'

test-artifacts:
    xcrun swift test --filter 'CommandSurfaceTests|CommandSurfaceGoldenTests|KnobDocumentationTests|DocumentationLinkTests|ResearchRegistryTests|ResearchManifestTests|RepoMapRegistryTests|MetallibArtifactTests|MetallibFallbackTests'

docc:
    ./Scripts/validate-docc.sh

research-check:
    just lifecycle-check

lifecycle-check:
    if [[ -n "${ASKI_SKIP_BUILD:-}" ]]; then xcrun swift run --skip-build BuildResearchIndex --check; else xcrun swift run BuildResearchIndex --check; fi

bench:
    xcrun swift package --disable-sandbox benchmark --target AskiBenchmarks --no-progress

regen-kernels:
    xcrun swift run BuildKernelLibrary

regen-vectors:
    xcrun swift run BuildStandardVectors

audit-vectors *args:
    xcrun swift run BuildStandardVectors --audit {{ args }}

regen-repo-map:
    xcrun swift run BuildRepoMap

repo-map-check:
    if [[ -n "${ASKI_SKIP_BUILD:-}" ]]; then xcrun swift run --skip-build BuildRepoMap --check; else xcrun swift run BuildRepoMap --check; fi

doctor *args:
    ./Scripts/repo-doctor.sh {{ args }}

release-preflight *args:
    ./Scripts/repo-doctor.sh {{ args }}

# Portable script regression tests (Python 3 standard library; fake Apple tools).
# Separate from the unchanged, macOS-only acceptance gate.
test-infra:
    python3 -B -m unittest discover -s Scripts/tests -p 'test_*.py' -v
