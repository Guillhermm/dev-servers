import Foundation

/// Maps a request path on the app's own URL scheme to a file under the UI directory.
public enum UIAssets {
    public static let scheme = "devservers"
    public static let host = "app"
    public static let pageURL = URL(string: "\(scheme)://\(host)/index.html")!

    static let types = [
        "html": "text/html", "js": "text/javascript", "css": "text/css",
        "json": "application/json", "svg": "image/svg+xml", "png": "image/png",
    ]

    /// nil for anything outside root, a directory, a missing file or an unknown type.
    public static func resolve(root: URL, path: String) -> (file: URL, mime: String)? {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.isEmpty else { return nil }
        let file = base.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(base.path + "/"),
              let mime = types[file.pathExtension.lowercased()] else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue
        else { return nil }
        return (file, mime)
    }

    public static func isPage(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == host && url.path == "/index.html"
    }
}
