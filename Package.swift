// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Burnbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Burnbar", targets: ["Burnbar"])
    ],
    targets: [
        .executableTarget(name: "Burnbar"),
        .testTarget(name: "BurnbarTests", dependencies: ["Burnbar"])
    ]
)
