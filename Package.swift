// swift-tools-version: 6.0
import PackageDescription

// Core is shared. Each system gets its own window: MacApp (AppKit + WKWebView) on macOS,
// LinuxApp (GTK 4 + WebKitGTK) on Linux. Only the window for the host system is declared, so
// neither build needs the other's toolkit.
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

var targets: [Target] = [
    .target(name: "Core", swiftSettings: swift5),
    .testTarget(name: "CoreTests", dependencies: ["Core"], swiftSettings: swift5),
]
var products: [Product] = []

#if os(macOS)
targets.append(.executableTarget(
    name: "DevServersMac", dependencies: ["Core"], path: "Sources/MacApp", swiftSettings: swift5))
products.append(.executable(name: "DevServersMac", targets: ["DevServersMac"]))
#elseif os(Linux)
targets.append(.systemLibrary(
    name: "CWebKitGTK", path: "Sources/CWebKitGTK", pkgConfig: "webkitgtk-6.0",
    providers: [.apt(["libwebkitgtk-6.0-dev"]), .yum(["webkitgtk6.0-devel"])]))
targets.append(.executableTarget(
    name: "DevServersLinux", dependencies: ["Core", "CWebKitGTK"], path: "Sources/LinuxApp",
    swiftSettings: swift5))
products.append(.executable(name: "DevServersLinux", targets: ["DevServersLinux"]))
#endif

let package = Package(
    name: "DevServers",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets)
