// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SnaPayCore",
    defaultLocalization: "he",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "SnaPayCore", targets: ["SnaPayCore"]),
    ],
    targets: [
        .target(name: "SnaPayCore"),
        .testTarget(name: "SnaPayCoreTests", dependencies: ["SnaPayCore"]),
    ]
)
