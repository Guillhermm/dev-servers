import Foundation

enum Paths {
    /// The cloned repo, which holds ui/ and registry.json. DEV_SERVERS_ROOT wins; otherwise walk up
    /// from the binary (.build/release/DevServersLinux) until a folder has ui/index.html.
    static let root: URL = {
        let env = ProcessInfo.processInfo.environment
        if let r = env["DEV_SERVERS_ROOT"], !r.isEmpty { return URL(fileURLWithPath: r) }
        let exe = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe"))
            ?? CommandLine.arguments[0]
        var dir = URL(fileURLWithPath: exe).resolvingSymlinksInPath().deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("ui/index.html").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    static let registry: URL = {
        if let o = ProcessInfo.processInfo.environment["DEV_SERVERS_REGISTRY"], !o.isEmpty {
            return URL(fileURLWithPath: o)
        }
        return root.appendingPathComponent("registry.json")
    }()

    static let ui = root.appendingPathComponent("ui")
}

/// Hands a URL or a file to the desktop's default app. argv only, never a shell.
enum Desktop {
    static func open(_ url: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        p.arguments = [url.isFileURL ? url.path : url.absoluteString]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        return true
    }
}
