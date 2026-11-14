// swift-tools-version: 6.3
import Foundation
import PackageDescription

let askiPath = ProcessInfo.processInfo.environment["ASKI_REPO_PATH"] ?? "../aski4"
let package = Package(
    name: "GIFMemoryHarness",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "gif-memory-harness", targets: ["GIFMemoryHarness"])],
    dependencies: [.package(name: "Aski", path: askiPath)],
    targets: [
        .executableTarget(
            name: "GIFMemoryHarness",
            dependencies: [.product(name: "Aski", package: "Aski")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
