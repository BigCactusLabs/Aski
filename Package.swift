// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Aski",
    platforms: [.iOS(.v18), .macOS(.v15), .visionOS(.v2)],
    products: [
        .library(name: "Aski", targets: ["Aski"]),
        .executable(name: "aski", targets: ["AskiCLIRunner"]),
        .executable(name: "AskiColorLab", targets: ["AskiColorLabRunner"]),
        .executable(name: "AskiMotionLab", targets: ["AskiMotionLabRunner"]),
        .executable(name: "AskiVideoLab", targets: ["AskiVideoLabRunner"]),
        .executable(name: "AskiAccessLab", targets: ["AskiAccessLabRunner"]),
        .executable(name: "AskiDecolorLab", targets: ["AskiDecolorLabRunner"]),
        .executable(name: "AskiHDRLab", targets: ["AskiHDRLabRunner"]),
        .executable(name: "AskiPresetLab", targets: ["AskiPresetLabRunner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.2.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", "1.18.7"..<"1.19.0"),
        .package(url: "https://github.com/ordo-one/package-benchmark", "1.31.0"..<"1.36.0"),
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.3"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "Aski",
            exclude: ["Effects/Kernels"],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
                .copy("Resources/Fonts"),
                .copy("Resources/ShapeData"),
                .copy("Resources/Kernels"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BuildStandardVectors",
            dependencies: ["Aski"],
            path: "Tools/BuildStandardVectors",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BuildKernelLibrary",
            path: "Tools/BuildKernelLibrary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BuildResearchIndex",
            path: "Tools/BuildResearchIndex",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BuildRepoMap",
            path: "Tools/BuildRepoMap",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiToolSupport",
            dependencies: [
                "Aski",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiToolSupport",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiDemo",
            dependencies: [
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiDemo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiTileMatrix",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiTileMatrix",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiColorLab",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiColorLab",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiColorLabRunner",
            dependencies: [
                "AskiColorLab",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiColorLabRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiMotionLab",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiMotionLab",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiMotionLabRunner",
            dependencies: [
                "AskiMotionLab",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiMotionLabRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiVideoLab",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiVideoLab",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiVideoLabRunner",
            dependencies: [
                "AskiVideoLab",
                "AskiToolSupport",
            ],
            path: "Tools/AskiVideoLabRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiAccessLab",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiAccessLab",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiAccessLabRunner",
            dependencies: [
                "AskiAccessLab",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiAccessLabRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiDecolorLab",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiDecolorLab",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiDecolorLabRunner",
            dependencies: [
                "AskiDecolorLab",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiDecolorLabRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiHDRLab",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiHDRLab",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiHDRLabRunner",
            dependencies: [
                "AskiHDRLab",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiHDRLabRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiPresetLab",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiPresetLab",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiPresetLabRunner",
            dependencies: [
                "AskiPresetLab",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiPresetLabRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AskiCLI",
            dependencies: [
                "AskiToolSupport",
                "AskiColorLab",
                "AskiMotionLab",
                "AskiVideoLab",
                "AskiAccessLab",
                "AskiDecolorLab",
                "AskiHDRLab",
                "AskiPresetLab",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/AskiCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiCLIRunner",
            dependencies: [
                "AskiCLI",
                "AskiToolSupport",
            ],
            path: "Tools/AskiCLIRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AskiBenchmarks",
            dependencies: [
                "Aski",
                .product(name: "Benchmark", package: "package-benchmark"),
            ],
            path: "Benchmarks/AskiBenchmarks",
            swiftSettings: [.swiftLanguageMode(.v6)],
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        ),
        .testTarget(
            name: "AskiTests",
            dependencies: [
                "Aski",
                "AskiToolSupport",
                "AskiCLI",
                "AskiColorLab",
                "AskiMotionLab",
                "AskiVideoLab",
                "AskiAccessLab",
                "AskiDecolorLab",
                "AskiHDRLab",
                "AskiPresetLab",
                "BuildStandardVectors",
                "BuildResearchIndex",
                "BuildRepoMap",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PropertyBased", package: "swift-property-based"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "Numerics", package: "swift-numerics"),
            ],
            exclude: ["__Snapshots__", "Goldens"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
