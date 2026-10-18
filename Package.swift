// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MovieMaker",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "MovieMaker", targets: ["MovieMaker"])],
    targets: [
        .target(name: "MovieCore"),
        .executableTarget(name: "MovieMaker", dependencies: ["MovieCore"]),
        // No XCTest/Testing on Command Line Tools; swap for a testTarget once Xcode is installed.
        .executableTarget(name: "CoreChecks", dependencies: ["MovieCore"]),
        // Newer checks, in several small files so they build in seconds: `swift build --product NewChecks`.
        .executableTarget(name: "NewChecks", dependencies: ["MovieCore"]),
    ]
)
