# Project: dev-servers

A macOS app, "Dev Servers", that lists every local server Guilherme's projects run, shows each
port and whether it is listening, and starts, stops, opens and shows the log of each one. The repo
is meant to be public (MIT): nothing personal is committed, and the app stays generic for other
users.

This project is not wired into `claude-code-agents`: by his decision its Claude context lives here,
at the repo root, and this file is committed. That is a deliberate exception to the global rule
that keeps Claude files out of his repos.

## The registry

`registry.json` at the repo root is the single list of servers, and the global rule makes every
project with a server add itself here. It is gitignored (it holds his paths and project names), so
registering a server is a local edit with no commit; `registry.example.json` is the committed
template and must stay free of anything personal. Each entry has `id` (`^[a-z0-9-]+$`), `name`, `path`, `cwd`,
`port`, `host`, `start` (an argv array, never a shell string), `env`, `url`, `health`, `managed`
and `notes`. `managed: false` marks services that are not his to stop (Ollama, open-webui,
Caddy): the app shows their status and never offers Stop. Ports are unique, except the Vite (5173) and
Astro (4321) defaults still shared by a few projects until each moves; new ones take the next free
84xx.

## Architecture

- **Swift shell with a native bridge, no server of its own, on macOS and Linux.** A Swift Package
  Manager package: a shared `Core` library and one window per system, `Sources/MacApp` (AppKit,
  WKWebView, `WKScriptMessageHandlerWithReply`) and `Sources/LinuxApp` (GTK 4, WebKitGTK 6.0,
  `script-message-with-reply-received`, through the C module in `Sources/CWebKitGTK`).
- **Platform split**: nothing outside `Sources/Core/Platform/` calls a system-specific API.
  `Platform.swift` lists what each system provides; `Platform/macOS/` and `Platform/Linux/` fill it
  in. Pure parsers (lsof, /proc) compile everywhere so their tests run on both. Keep new
  system-specific code in those folders or in the matching app target.
- **The page sends only an id and an action** (`list`, `status`, `start`, `stop`,
  `confirmStop`, `open`, `log`, `tail`); `confirmStop` also carries the pid the user was shown. Commands, paths and ports come from the registry, never from the page.
- **Environment**: the user's shell environment is read once with `$SHELL -ilc env` (and again on
  Reload Registry). A login shell alone misses nvm and friends, which live in `.zshrc`; that was
  why every npm entry failed with exit 127 when the app was opened from Finder.
- **Start** runs the registry argv through `/bin/sh -c` with positional arguments (no
  interpolation), in its own session (`POSIX_SPAWN_SETSID`) so it outlives the app. Logs go to
  `Platform.logDirectory` (`~/Library/Logs/Dev Servers` on macOS, `~/.local/state/dev-servers/logs`
  on Linux), directory 700 and files 600.
- **Start failures** come back in `status` as `launch` (exit reason and log tail, from `waitpid`);
  the page turns them into footer notices (`launchNotices` in `ui/state.js`).
- **Stop** signals only a process that listens on that entry's registered port, is owned by the
  user, and was started by the app or runs from inside the entry's `path`; anything else is shown
  with its PID and command and needs confirmation. SIGTERM to the group, SIGKILL after 5 s. A
  listener counts as started by the app when its process group is one the app spawned, so a
  server behind `npm run` is recognized.
- **Status**: `Platform.listeners()`, one `lsof -nP -iTCP -sTCP:LISTEN -a -u $UID -F pcn` on macOS
  and `/proc/net/tcp{,6}` plus `/proc/<pid>/fd` on Linux, per poll (every 2 s, paused when
  hidden), matched to registered ports.
- **UI**: plain HTML and ES modules in `ui/`, DOM built with `textContent`, strict CSP. The window
  loads it from `devservers://app/` (a `WKURLSchemeHandler` over `ui/`, no path outside it), never
  `file://`, where WebKit refuses module scripts; only that page may call the bridge.
- **Packaging**: `tools/macos/build_app.sh` builds `build/Dev Servers.app` (gitignored), signs ad
  hoc and links it into `~/Applications`. `tools/linux/install.sh` builds the release binary and
  installs a `.desktop` entry, the icon and `~/.local/bin/dev-servers`.

## Running and checking

- `swift test` for the core; `node --test` for the UI logic.
- The app is checked by launching it and starting and stopping a real server.
- Linux is checked in a container: an Ubuntu 24.04 image with `swift:6.1-noble`,
  `libwebkitgtk-6.0-dev`, `libgtk-4-dev`, `xvfb`, `xdotool`, run through Colima. Run `swift test`
  there, then the window under Xvfb with `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` (only because
  bubblewrap cannot run inside the container) and drive it with xdotool.
