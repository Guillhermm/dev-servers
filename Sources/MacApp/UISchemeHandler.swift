import Core
import Foundation
import WebKit

// WebKit blocks module scripts on file:// pages, so the UI is served from a scheme of our own.
final class UISchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) { self.root = root }

    func webView(_ w: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == UIAssets.host,
              let (file, mime) = UIAssets.resolve(root: root, path: url.path),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "\(mime); charset=utf-8", "Cache-Control": "no-store"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ w: WKWebView, stop task: WKURLSchemeTask) {}
}
