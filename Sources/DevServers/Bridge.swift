import AppKit
import Core
import WebKit

/// Forwards `{action, id?, pid?}` messages to the core service and replies with plain JSON.
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "devServers"
    let service: Service

    init(service: Service) { self.service = service }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        // Only the app's own page may drive the bridge.
        guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, url.isFileURL,
              url.standardizedFileURL.path == Paths.page.standardizedFileURL.path else {
            return (nil, "forbidden")
        }
        guard let body = message.body as? [String: Any] else { return (nil, "bad message") }
        let action = body["action"] as? String
        let id = body["id"] as? String
        let pid = (body["pid"] as? NSNumber).flatMap { Int32(exactly: $0.doubleValue) }
        let service = self.service
        let result = await Task.detached { service.handle(action: action, id: id, pid: pid) }.value
        return (result, nil)
    }
}
