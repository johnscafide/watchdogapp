// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WatchdogCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WatchdogCore", targets: ["WatchdogCore"])],
    targets: [
        .target(name: "WatchdogCore"),
        .testTarget(name: "WatchdogCoreTests", dependencies: ["WatchdogCore"])
    ]
)
