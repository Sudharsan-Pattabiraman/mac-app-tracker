// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TikTik",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TikTik", targets: ["TikTik"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        // Platform-independent logic (Foundation only). Unit-tested.
        .target(
            name: "TikTikCore",
            path: "Sources/TikTikCore"
        ),
        // Persistence and queries (GRDB). No AppKit, so it's testable anywhere.
        .target(
            name: "TikTikStore",
            dependencies: [
                "TikTikCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/TikTikStore"
        ),
        // The macOS app. Resources are copied into TikTik.app by run.sh, not by SwiftPM,
        // so the bundle layout stays standard and code signing stays valid.
        .executableTarget(
            name: "TikTik",
            dependencies: ["TikTikCore", "TikTikStore"],
            path: "Sources/TikTik",
            exclude: ["Resources"]
        ),
        // Unit checks for TikTikCore. A plain executable rather than an XCTest target,
        // because XCTest isn't available with the Command Line Tools alone.
        // Run with `./run.sh test`.
        .executableTarget(
            name: "TikTikChecks",
            dependencies: ["TikTikCore", "TikTikStore"],
            path: "Checks"
        ),
    ]
)
