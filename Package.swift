// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Samvaad",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "Samvaad", targets: ["Samvaad"]),
    ],
    targets: [
        .target(
            name: "Samvaad",
            path: "Sources/Samvaad"
        ),
        .testTarget(
            name: "SamvaadTests",
            dependencies: ["Samvaad"],
            path: "Tests/SamvaadTests"
        ),
    ]
)
