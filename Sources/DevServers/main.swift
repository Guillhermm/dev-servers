import AppKit
import Core
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var service: Service!

    func applicationDidFinishLaunching(_ note: Notification) {
        service = Service(
            registryURL: Paths.registry,
            openURL: { NSWorkspace.shared.open($0) },
            openLog: { url in
                let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
                NSWorkspace.shared.open([url], withApplicationAt: console,
                                        configuration: NSWorkspace.OpenConfiguration())
                return true
            })

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addScriptMessageHandler(
            Bridge(service: service), contentWorld: .page, name: Bridge.name)

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Dev Servers"
        window.minSize = NSSize(width: 560, height: 420)
        window.contentView = web
        window.setFrameAutosaveName("DevServersWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)

        buildMenu()
        load()
        NSApp.activate(ignoringOtherApps: true)
    }

    func load() {
        guard FileManager.default.fileExists(atPath: Paths.page.path) else {
            web.loadHTMLString(
                "<body style=\"font:0.9375rem -apple-system;padding:2rem\">Missing \(Paths.page.path.htmlEscaped)</body>",
                baseURL: nil)
            return
        }
        web.loadFileURL(Paths.page, allowingReadAccessTo: Paths.repo.appendingPathComponent("ui"))
    }

    @objc func reload() {
        service.reload()
        load()
    }

    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = action.request.url else { return decisionHandler(.cancel) }
        if u.absoluteString == "about:blank"
            || (u.isFileURL && u.standardizedFileURL.path == Paths.page.standardizedFileURL.path) {
            return decisionHandler(.allow)
        }
        if action.navigationType == .linkActivated, u.scheme == "http" || u.scheme == "https" {
            NSWorkspace.shared.open(u)
        }
        decisionHandler(.cancel)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dev Servers",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reload Registry", action: #selector(reload), keyEquivalent: "r")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen",
                         action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = winMenu
        main.addItem(winItem)

        NSApp.mainMenu = main
    }
}

extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
