# Dev Servers

A small macOS app that lists the local servers your projects run, shows each port and whether
something is listening on it, and starts, stops, opens and shows the log of each one.

It is a Swift shell around a WKWebView. The page in `ui/` talks to the app through a native
message bridge; there is no HTTP server of its own and no third-party dependency.

## Requirements

- macOS 13 or later.
- Xcode command line tools (Swift 6), to build.
- Node.js, only to run the UI tests.

## Getting started

```sh
git clone <this repo> dev-servers && cd dev-servers
cp registry.example.json registry.json   # then list your own servers in it
tools/build_app.sh                        # builds build/Dev Servers.app and links it into ~/Applications
```

`registry.json` is yours and is gitignored. The bundle reads `ui/` and `registry.json` from the
cloned folder at run time, so after editing the registry use View > Reload Registry (⌘R).
`DEV_SERVERS_REGISTRY=/path/to/registry.json` points the app at a registry elsewhere.

## Registry format

`{ "version": 1, "servers": [...] }`. Each entry:

- `id`: `^[a-z0-9-]+$`, unique.
- `name`, `notes`: display text.
- `path`: the project directory. `cwd`: the working directory for `start`. Both absolute and,
  for managed entries, inside your home folder.
- `port` (1024–65535), `host`, `url` (http or https), `health`: `{ "type": "tcp" }`.
- `start`: the command as an argv array, never a shell string. It must run the server in the
  foreground.
- `env`: extra environment variables for that server.
- `managed`: `false` for services the app must never stop (a Homebrew service, a launchd agent).
  The app shows their status; their `start` is only documentation.

Give each server its own port and pass it on the command line (`--port 8402 --strictPort` for
Vite) so a busy port fails instead of moving. Two entries may share a port only if both `notes`
say "shared"; while something listens there, both rows show "Port shared".

`node --test` validates `registry.example.json` and, when present, your `registry.json`,
including that every `path` and `cwd` exists.

## How it starts and stops servers

- **Environment**: the app reads your shell's environment once (`$SHELL -ilc env`), the same one
  a new terminal tab gets, so tools installed through nvm, pyenv, asdf or Homebrew are found even
  when the app is opened from Finder. View > Reload Registry reads it again.
- **Start**: `/bin/sh -c` with the entry's `cwd` and `start` passed as positional arguments,
  never interpolated into the script, in a new session so the server outlives the app. Output goes to
  `~/Library/Logs/Dev Servers/<id>.log` (mode 600; the previous run is kept as `.log.1`).
- **Start failures**: if the process exits before its port answers, a notice at the bottom of
  the window says why (for example `command not found (exit 127)`) with the last lines of the
  log. If it keeps running but nothing listens on the port after 30 s, a warning says so.
- **Log**: shows the end of the log inside the app, with a button to open it in Console.
- **Stop**: only a process listening on the entry's own port, owned by you, and either started by
  the app (same process group) or running from inside the entry's `path`. Anything else is shown
  with its PID and command and needs confirmation. SIGTERM to the group, SIGKILL after 5 s.
- **Status**: one `lsof -nP -iTCP -sTCP:LISTEN -a -u $UID` every 2 s while the window is visible.

## Security model

- The registry is trusted configuration: whoever can write it can run commands as you, exactly
  like your shell startup files. Keep it in your home folder and out of shared directories.
- Servers inherit your shell environment, as they would from a terminal. Put secrets in each
  project's own config, not in `registry.json`, which is never committed.
- The page can only send an action and an id; commands, paths and ports always come from the
  registry. Only the app's own page (`devservers://app/index.html`, main frame) can reach the
  bridge, the page has a strict Content Security Policy and builds the DOM with `textContent`.
- `open` accepts only http and https URLs from the registry.

## Development

- `swift test`: the core (registry validation, `lsof` parsing, launch plan, stop policy, shell
  environment, exit reports) and integration tests that start and stop real processes.
- `node --test`: UI state logic and registry checks.
- Opening `ui/index.html` in a browser shows the static registry with actions disabled. Serve
  the repo root (`python3 -m http.server 8497`) so `registry.json` can be fetched.

### Bridge contract

`window.webkit.messageHandlers.devServers.postMessage({ action, id?, pid? })`:

- `list` returns `[{ id, name, port, url, managed, notes }]`.
- `status` returns `[{ id, listening, pid, command, ownedByApp, launch? }]`, where `launch` is
  the latest start from this app session: `{ pid, running }`, plus `{ reason, code, signal,
  expected, log }` once it has exited (`expected` is true when the app stopped it).
- `start`, `stop`, `confirmStop` return `{ ok, error?, needsConfirmation?, pid?, command? }`.
  `confirmStop` must carry the `pid` that was shown and is refused if the listener changed.
- `tail` returns `{ ok, text, path }`: the last 64 KB of the log.
- `open`, `log` return `{ ok }`.

When the registry is missing or invalid, every action returns `{ ok: false, error }`; the page
shows the error until View > Reload Registry.

## License

MIT, see [LICENSE](LICENSE).
