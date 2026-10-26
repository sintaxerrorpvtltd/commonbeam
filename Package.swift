// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Commonbeam", platforms: [.macOS("26.0")],
    products: [.library(name: "CommonbeamCore", targets: ["CommonbeamCore"]),
               .executable(name: "Commonbeam", targets: ["CommonbeamApp"]),
               .executable(name: "CommonbeamFixtureServer", targets: ["CommonbeamFixtureServer"])],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.28.0", traits: []),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.34.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0")
    ],
    targets: [
        .target(name: "CommonbeamCore"),
        .target(name: "CommonbeamHTTP", dependencies: ["CommonbeamCore", .product(name: "Hummingbird", package: "hummingbird"), .product(name: "HummingbirdCore", package: "hummingbird"), .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOHTTPTypes", package: "swift-nio-extras"), .product(name: "Logging", package: "swift-log")]),
        .executableTarget(name: "CommonbeamApp", dependencies: ["CommonbeamCore", "CommonbeamHTTP"]),
        .executableTarget(name: "CommonbeamFixtureServer", dependencies: ["CommonbeamCore", "CommonbeamHTTP"]),
        .testTarget(name: "CommonbeamCoreTests", dependencies: ["CommonbeamCore"]),
        .testTarget(name: "CommonbeamHTTPTests", dependencies: ["CommonbeamHTTP", .product(name: "HummingbirdTesting", package: "hummingbird")])
    ]
)
