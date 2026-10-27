import Foundation

enum Paths {
    /// build/Dev Servers.app -> build -> repo. The bundle is symlinked into ~/Applications,
    /// so resolve the link first. Outside a bundle (swift run) fall back to the working directory.
    static let repo: URL = {
        let bundle = URL(fileURLWithPath: Bundle.main.bundlePath).resolvingSymlinksInPath()
        if bundle.pathExtension == "app" {
            return bundle.deletingLastPathComponent().deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    static let registry: URL = {
        if let o = ProcessInfo.processInfo.environment["DEV_SERVERS_REGISTRY"], !o.isEmpty {
            return URL(fileURLWithPath: o)
        }
        return repo.appendingPathComponent("registry.json")
    }()

    static let page = repo.appendingPathComponent("ui/index.html")
}
