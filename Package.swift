// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevServers",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DevServers", targets: ["DevServers"]),
    ],
    targets: [
        .target(name: "Core", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "DevServers",
            dependencies: ["Core"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ])
