// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimilarVideoFinder",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SimilarVideoFinder", targets: ["SimilarVideoFinder"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SimilarVideoFinder",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/SimilarVideoFinder"
        ),
        .testTarget(
            name: "SimilarVideoFinderTests",
            dependencies: ["SimilarVideoFinder"],
            path: "Tests/SimilarVideoFinderTests"
        )
    ]
)
