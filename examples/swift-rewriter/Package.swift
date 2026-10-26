// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SwiftRewriter", platforms: [.macOS("26.0")], dependencies: [.package(path: "../../packages/CommonbeamKit")], targets: [.executableTarget(name: "SwiftRewriter", dependencies: [.product(name: "CommonbeamKit", package: "CommonbeamKit")], path: "Sources")])
