// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AstraTest",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "AstraTest", targets: ["AstraTest"])],
    targets: [
        .target(name: "AstraTest", path: "Sources/AstraTest"),
        .testTarget(name: "AstraTestTests", dependencies: ["AstraTest"], path: "Tests/AstraTestTests"),
    ]
)
