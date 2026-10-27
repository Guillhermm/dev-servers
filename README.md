# Dev Servers

A macOS app that lists every local server my projects run, shows each port and whether it is
listening, and starts, stops, opens and shows the log of each one. A Swift shell hosts a
WKWebView; the page in `ui/` talks to it through a native message bridge.

## Build and run

- `node --test`: UI logic and registry checks.
- `swift test`: the Swift core (Package.swift, Sources/, Tests/).
- `tools/build_app.sh`: builds `build/Dev Servers.app`, signs it ad hoc and links it into
  `~/Applications`. The bundle reads `ui/` and `registry.json` from this repo at run time.
- Opening `ui/index.html` in a plain browser shows a notice and the static registry list, with
  actions disabled. Serve the repo root (`python3 -m http.server 8497`) so `registry.json` can be
  fetched; from `file://` the list is empty.

## Registry format

`registry.json` at the repo root: `{ "version": 1, "servers": [...] }`. Each entry:

- `id`: `^[a-z0-9-]+$`, unique.
- `name`, `notes`: display text.
- `path`: the project directory. `cwd`: the working directory for `start`.
- `port`, `host`, `url`, `health`: `{ "type": "tcp" }`.
- `start`: argv array, never a shell string.
- `env`: extra environment variables.
- `managed`: `false` for services the app must never stop (Ollama, open-webui, Caddy). Their
  `start` is only documentation.

Ports are unique, except Vite's 5173 and Astro's 4321 defaults, which several projects share.
Either entry on a shared port can be started while the port is free; once something listens
there, both rows show "Port shared", since the app cannot tell which project it is. Each of them
moves to its own 84xx port the next time its repo is touched.

## Registering a project

Add one entry to `registry.json`: a free port from the 84xx range (the next after 8423), the
exact argv that starts the server in the foreground, and `env` for any port override. Run
`node --test`: it checks the id, port uniqueness, argv and that the paths exist.

## Bridge contract

The page calls `window.webkit.messageHandlers.devServers.postMessage({ action, ... })`:

- `list` returns `[{ id, name, port, url, managed, notes }]`.
- `status` returns `[{ id, listening, pid, command, ownedByApp }]`.
- `start`, `stop`, `confirmStop` return `{ ok, error?, needsConfirmation?, pid?, command? }`.
- `open`, `log` return `{ ok }`.

When `registry.json` is invalid, every action, `list` and `status` included, returns
`{ ok: false, error }`; the page shows the error and stops polling until View > Reload Registry.

The page sends only an id and an action. `confirmStop` must carry the `pid` that was shown, and
is refused when the listener on the port is no longer that pid. Only the app's own
`ui/index.html`, in the main frame, can reach the bridge.
