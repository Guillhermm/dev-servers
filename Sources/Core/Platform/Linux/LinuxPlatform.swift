#if os(Linux)
import Foundation
import Glibc

extension Platform {
    public static let name = "Linux"
    public static let defaultShell = "/bin/bash"
    /// glibc's POSIX_SPAWN_SETSID (2.26+); the macro is only visible under _GNU_SOURCE.
    public static let spawnNewSession: Int32 = 0x80
    public typealias FileActions = posix_spawn_file_actions_t
    public typealias SpawnAttributes = posix_spawnattr_t
    static var blankFileActions: FileActions { FileActions() }
    static var blankSpawnAttributes: SpawnAttributes { SpawnAttributes() }

    /// `$XDG_STATE_HOME/dev-servers/logs`, by default `~/.local/state/dev-servers/logs`.
    public static let logDirectory: URL = {
        let env = ProcessInfo.processInfo.environment["XDG_STATE_HOME"] ?? ""
        let state = env.hasPrefix("/") ? URL(fileURLWithPath: env)
            : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/state")
        return state.appendingPathComponent("dev-servers/logs")
    }()

    /// Reads /proc instead of running lsof, which many distributions do not install. Sockets are
    /// matched to processes through /proc/<pid>/fd, which only shows the user's own processes.
    public static func listeners(uid: uid_t = getuid()) -> [Listener] {
        var sockets: [UInt64: ProcNetSocket] = [:]
        for file in ["/proc/net/tcp", "/proc/net/tcp6"] {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for s in ProcParser.listening(text) where s.uid == uid { sockets[s.inode] = s }
        }
        guard !sockets.isEmpty else { return [] }

        let fm = FileManager.default
        var result: [Listener] = []
        for entry in (try? fm.contentsOfDirectory(atPath: "/proc")) ?? [] {
            guard let pid = Int32(entry) else { continue }
            let fdDir = "/proc/\(pid)/fd"
            guard let fds = try? fm.contentsOfDirectory(atPath: fdDir) else { continue }
            var seen = Set<UInt64>()
            for fd in fds {
                guard let link = try? fm.destinationOfSymbolicLink(atPath: "\(fdDir)/\(fd)"),
                      let inode = ProcParser.socketInode(link: link), let s = sockets[inode],
                      seen.insert(inode).inserted else { continue }
                let comm = (try? String(contentsOfFile: "/proc/\(pid)/comm", encoding: .utf8))?
                    .trimmingCharacters(in: .newlines) ?? ""
                result.append(Listener(pid: pid, command: comm, port: s.port, address: s.address))
            }
        }
        return result
    }

    public static func processFacts(pid: Int32) -> ProcessFacts? {
        guard let status = try? String(contentsOfFile: "/proc/\(pid)/status", encoding: .utf8),
              let uid = ProcParser.uid(status: status) else { return nil }
        let cwd = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/\(pid)/cwd")
        return ProcessFacts(uid: uid, cwd: cwd)
    }
}
#endif
