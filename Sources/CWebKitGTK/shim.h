#ifndef DEV_SERVERS_SHIM_H
#define DEV_SERVERS_SHIM_H

#include <gtk/gtk.h>
#include <webkit/webkit.h>

// GLib's casting macros and g_signal_connect are macros, which Swift cannot import. These
// inline wrappers are the only C in the Linux shell.

static inline gulong ds_connect(gpointer instance, const char *signal, GCallback callback, gpointer data) {
    return g_signal_connect_data(instance, signal, callback, data, NULL, (GConnectFlags)0);
}

static inline GtkWindow *ds_window(gpointer p) { return GTK_WINDOW(p); }
static inline GtkApplication *ds_application(gpointer p) { return GTK_APPLICATION(p); }
static inline GApplication *ds_gapplication(gpointer p) { return G_APPLICATION(p); }
static inline GActionMap *ds_action_map(gpointer p) { return G_ACTION_MAP(p); }
static inline GAction *ds_action(gpointer p) { return G_ACTION(p); }
static inline WebKitWebView *ds_web_view(gpointer p) { return WEBKIT_WEB_VIEW(p); }
static inline WebKitPolicyDecision *ds_policy_decision(gpointer p) { return WEBKIT_POLICY_DECISION(p); }
static inline WebKitNavigationPolicyDecision *ds_navigation_decision(gpointer p) {
    return WEBKIT_NAVIGATION_POLICY_DECISION(p);
}

#endif
