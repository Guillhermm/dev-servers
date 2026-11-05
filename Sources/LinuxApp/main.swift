import CWebKitGTK
import Core
import Foundation

// The Linux window: GTK 4 and WebKitGTK 6. It mirrors MacApp: the page in ui/ is served from
// devservers://app/, and only that page may call the bridge. All server logic is in Core.

let appID = "systems.zenus.DevServers"
let service = Service(registryURL: Paths.registry, openURL: Desktop.open, openLog: Desktop.open)
var webView: gpointer?

func warmEnvironment() {
    DispatchQueue.global(qos: .utility).async { _ = service.baseEnvironment() }
}

func loadPage() {
    guard let webView else { return }
    webkit_web_view_load_uri(ds_web_view(webView), UIAssets.pageURL.absoluteString)
}

/// Runs `work` on GTK's main loop. Dispatch's main queue is never drained under GTK.
func onMainLoop(_ work: @escaping () -> Void) {
    let box = Unmanaged.passRetained(Box(work)).toOpaque()
    g_idle_add_full(G_PRIORITY_DEFAULT, { data in
        Unmanaged<Box>.fromOpaque(data!).takeRetainedValue().work()
        return gboolean(0)
    }, box, nil)
}

/// GTK objects held across the hop to a worker thread. They are only touched again on the main
/// loop, which is what makes the unchecked Sendable safe.
struct Pending: @unchecked Sendable {
    let context: OpaquePointer?
    let reply: OpaquePointer
}

final class Box {
    let work: () -> Void
    init(_ work: @escaping () -> Void) { self.work = work }
}

// MARK: - devservers:// scheme

let serveUI: WebKitURISchemeRequestCallback = { request, _ in
    guard let request else { return }
    let uri = webkit_uri_scheme_request_get_uri(request).map { String(cString: $0) } ?? ""
    let path = webkit_uri_scheme_request_get_path(request).map { String(cString: $0) } ?? ""
    guard URL(string: uri)?.host == UIAssets.host,
          let (file, mime) = UIAssets.resolve(root: Paths.ui, path: path),
          let data = try? Data(contentsOf: file) else {
        let error = g_error_new_literal(g_quark_from_static_string("devservers"), 404, "not found")
        webkit_uri_scheme_request_finish_error(request, error)
        g_error_free(error)
        return
    }
    let bytes = data.withUnsafeBytes { g_bytes_new($0.baseAddress, gsize($0.count)) }
    let stream = g_memory_input_stream_new_from_bytes(bytes)
    webkit_uri_scheme_request_finish(request, stream, gint64(data.count), "\(mime); charset=utf-8")
    g_object_unref(stream)
    g_bytes_unref(bytes)
}

// MARK: - bridge

typealias ReplyCallback = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?, gpointer?) -> gboolean

/// `script-message-with-reply-received`: (manager, JSCValue, WebKitScriptMessageReply, data).
let onMessage: ReplyCallback = { _, value, reply, _ in
    guard let value, let reply else { return gboolean(0) }
    // WebKitGTK gives no frame for a message, so check the page the view shows. Navigation is
    // limited to that page (decide-policy) and its CSP allows no frames.
    let current = webView.flatMap { webkit_web_view_get_uri(ds_web_view($0)) }.map { String(cString: $0) }
    guard let current, let url = URL(string: current), UIAssets.isPage(url) else {
        webkit_script_message_reply_return_error_message(reply, "forbidden")
        return gboolean(1)
    }
    guard let json = jsc_value_to_json(value, 0) else {
        webkit_script_message_reply_return_error_message(reply, "bad message")
        return gboolean(1)
    }
    let text = String(cString: json)
    g_free(json)
    guard let body = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
        webkit_script_message_reply_return_error_message(reply, "bad message")
        return gboolean(1)
    }
    let action = body["action"] as? String
    let id = body["id"] as? String
    let pid = (body["pid"] as? NSNumber).flatMap { Int32(exactly: $0.doubleValue) }

    let pending = Pending(context: jsc_value_get_context(value), reply: reply)
    g_object_ref(gpointer(pending.context))
    webkit_script_message_reply_ref(reply)
    DispatchQueue.global(qos: .userInitiated).async {
        let (context, reply) = (pending.context, pending.reply)
        let result = service.handle(action: action, id: id, pid: pid)
        let out = (try? JSONSerialization.data(withJSONObject: result)).map { String(decoding: $0, as: UTF8.self) }
        onMainLoop {
            if let out, let js = jsc_value_new_from_json(context, out) {
                webkit_script_message_reply_return_value(reply, js)
                g_object_unref(gpointer(js))
            } else {
                webkit_script_message_reply_return_error_message(reply, "could not encode the reply")
            }
            webkit_script_message_reply_unref(reply)
            g_object_unref(gpointer(context))
        }
    }
    return gboolean(1)
}

// MARK: - navigation

typealias PolicyCallback = @convention(c) (OpaquePointer?, gpointer?, WebKitPolicyDecisionType, gpointer?) -> gboolean

/// Only the app page loads in the window. A link the user clicks to http or https opens in the
/// default browser; everything else is dropped.
let decidePolicy: PolicyCallback = { _, decision, type, _ in
    guard let decision else { return gboolean(0) }
    guard type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION
            || type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION else { return gboolean(0) }
    let action = webkit_navigation_policy_decision_get_navigation_action(ds_navigation_decision(decision))
    let request = webkit_navigation_action_get_request(action)
    let uri = webkit_uri_request_get_uri(request).map { String(cString: $0) } ?? ""
    if let url = URL(string: uri) {
        if type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION, uri == "about:blank" || UIAssets.isPage(url) {
            webkit_policy_decision_use(ds_policy_decision(decision))
            return gboolean(1)
        }
        let userClick = webkit_navigation_action_get_navigation_type(action) == WEBKIT_NAVIGATION_TYPE_LINK_CLICKED
        if userClick, url.scheme == "http" || url.scheme == "https" { _ = Desktop.open(url) }
    }
    webkit_policy_decision_ignore(ds_policy_decision(decision))
    return gboolean(1)
}

// MARK: - application

typealias ActionCallback = @convention(c) (OpaquePointer?, OpaquePointer?, gpointer?) -> Void

func addAction(_ app: gpointer, _ name: String, accel: String, _ callback: ActionCallback) {
    let action = g_simple_action_new(name, nil)
    ds_connect(gpointer(action), "activate", unsafeBitCast(callback, to: GCallback.self), app)
    g_action_map_add_action(ds_action_map(app), ds_action(gpointer(action)))
    var accels: [UnsafePointer<CChar>?] = [UnsafePointer(strdup(accel)), nil]
    gtk_application_set_accels_for_action(ds_application(app), "app.\(name)", &accels)
    free(UnsafeMutablePointer(mutating: accels[0]))
    g_object_unref(gpointer(action))
}

typealias ActivateCallback = @convention(c) (gpointer?, gpointer?) -> Void

let activate: ActivateCallback = { app, _ in
    guard let app else { return }
    if webView != nil { return }

    let view = webkit_web_view_new()!
    webView = gpointer(view)
    let context = webkit_web_view_get_context(ds_web_view(webView))
    webkit_web_context_register_uri_scheme(context, UIAssets.scheme, serveUI, nil, nil)
    let security = webkit_web_context_get_security_manager(context)
    webkit_security_manager_register_uri_scheme_as_secure(security, UIAssets.scheme)
    webkit_security_manager_register_uri_scheme_as_cors_enabled(security, UIAssets.scheme)

    let manager = webkit_web_view_get_user_content_manager(ds_web_view(webView))
    webkit_user_content_manager_register_script_message_handler_with_reply(manager, Bridge.name, nil)
    ds_connect(gpointer(manager), "script-message-with-reply-received::\(Bridge.name)",
               unsafeBitCast(onMessage, to: GCallback.self), nil)
    ds_connect(webView, "decide-policy", unsafeBitCast(decidePolicy, to: GCallback.self), nil)

    let window = gtk_application_window_new(ds_application(app))!
    gtk_window_set_title(ds_window(window), "Dev Servers")
    gtk_window_set_default_size(ds_window(window), 980, 720)
    gtk_window_set_child(ds_window(window), view)

    addAction(app, "reload", accel: "<Control>r") { _, _, _ in
        service.reload()
        warmEnvironment()
        loadPage()
    }
    addAction(app, "quit", accel: "<Control>q") { _, _, app in
        g_application_quit(ds_gapplication(app))
    }

    warmEnvironment()
    loadPage()
    gtk_window_present(ds_window(window))
}

enum Bridge { static let name = "devServers" }

let app = gtk_application_new(appID, G_APPLICATION_DEFAULT_FLAGS)
ds_connect(gpointer(app), "activate", unsafeBitCast(activate, to: GCallback.self), nil)
let status = g_application_run(ds_gapplication(gpointer(app)), CommandLine.argc, CommandLine.unsafeArgv)
g_object_unref(gpointer(app))
exit(status)
