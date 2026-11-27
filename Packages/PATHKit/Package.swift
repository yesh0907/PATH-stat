// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PATHKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PATHKit", targets: ["PATHKit"]),
        .executable(name: "path-live", targets: ["path-live"]),
    ],
    targets: [
        .target(name: "PATHKit"),
        .executableTarget(name: "path-live", dependencies: ["PATHKit"]),
        .testTarget(
            name: "PATHKitTests",
            dependencies: ["PATHKit"],
            resources: [
                .copy("Resources/ridepath.json"),
                .copy("Resources/alerts.json"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
