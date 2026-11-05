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

- **Swift shell with a native bridge, no server of its own.** A Swift Package Manager package: a
  `Core` library (registry validation, `lsof` parsing, launch plan, stop policy) with no AppKit,
  and an app target with the WKWebView window and a `WKScriptMessageHandlerWithReply` bridge.
- **The page sends only an id and an action** (`list`, `status`, `start`, `stop`,
  `confirmStop`, `open`, `log`, `tail`); `confirmStop` also carries the pid the user was shown. Commands, paths and ports come from the registry, never from the page.
- **Environment**: the user's shell environment is read once with `$SHELL -ilc env` (and again on
  Reload Registry). A login shell alone misses nvm and friends, which live in `.zshrc`; that was
  why every npm entry failed with exit 127 when the app was opened from Finder.
- **Start** runs the registry argv through `/bin/sh -c` with positional arguments (no
  interpolation), in its own session (`POSIX_SPAWN_SETSID`) so it outlives the app. Logs go to
  `~/Library/Logs/Dev Servers/<id>.log`, directory 700 and files 600.
- **Start failures** come back in `status` as `launch` (exit reason and log tail, from `waitpid`);
  the page turns them into footer notices (`launchNotices` in `ui/state.js`).
- **Stop** signals only a process that listens on that entry's registered port, is owned by the
  user, and was started by the app or runs from inside the entry's `path`; anything else is shown
  with its PID and command and needs confirmation. SIGTERM to the group, SIGKILL after 5 s. A
  listener counts as started by the app when its process group is one the app spawned, so a
  server behind `npm run` is recognized.
- **Status**: one `lsof -nP -iTCP -sTCP:LISTEN -a -u $UID -F pcn` per poll (every 2 s, paused when
  hidden), matched to registered ports.
- **UI**: plain HTML and ES modules in `ui/`, DOM built with `textContent`, strict CSP. The window
  loads it from `devservers://app/` (a `WKURLSchemeHandler` over `ui/`, no path outside it), never
  `file://`, where WebKit refuses module scripts; only that page may call the bridge.
- **Packaging**: `tools/build_app.sh` builds `build/Dev Servers.app` (gitignored), signs ad hoc and
  links it into `~/Applications`.

## Running and checking

- `swift test` for the core; `node --test` for the UI logic.
- The app is checked by launching it and starting and stopping a real server.
