// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CSVCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CSVCore", targets: ["CSVCore"]),
    ],
    targets: [
        .target(name: "CSVCore"),
        .testTarget(
            name: "CSVCoreTests",
            dependencies: ["CSVCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
