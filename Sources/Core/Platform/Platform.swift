import Foundation

/// Everything the core needs from the operating system, in one place. Each supported system
/// fills it in from its own folder, and nothing outside `Platform/` calls a system-specific API:
///
/// - `Platform/macOS/MacPlatform.swift`: lsof, `proc_pidinfo`, `~/Library/Logs/Dev Servers`.
/// - `Platform/Linux/LinuxPlatform.swift`: `/proc`, `~/.local/state/dev-servers/logs`.
///
/// Members each one provides:
///
/// - `listeners(uid:)`: TCP sockets in LISTEN state owned by `uid`.
/// - `processFacts(pid:)`: owner and working directory of a process, or nil if unreadable.
/// - `logDirectory`: where server logs go.
/// - `defaultShell`: used when `$SHELL` is unset.
/// - `spawnNewSession`: the `POSIX_SPAWN_SETSID` flag value.
/// - `FileActions`, `SpawnAttributes` and their blank values: the `posix_spawn` handle types,
///   an optional pointer on macOS and a struct on Linux.
public enum Platform {}

#if !os(macOS) && !os(Linux)
#error("Dev Servers supports macOS and Linux only.")
#endif
