// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HeadControlCore", platforms: [.macOS(.v15)], products: [.library(name: "HeadControlCore", targets: ["HeadControlCore"])], targets: [.target(name: "HeadControlCore"), .testTarget(name: "HeadControlCoreTests", dependencies: ["HeadControlCore"])])
