// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CommonbeamKit", platforms: [.macOS("26.0")], products: [.library(name: "CommonbeamKit", targets: ["CommonbeamKit"])], targets: [.target(name: "CommonbeamKit"), .testTarget(name: "CommonbeamKitTests", dependencies: ["CommonbeamKit"])])
