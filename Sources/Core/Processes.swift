#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// POSIX process queries that behave the same on macOS and Linux. What differs per system
/// (who owns a pid, where it runs) lives in Platform.
public enum ProcessProbe {
    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// The process group of `pid`, or nil when it is gone.
    public static func group(of pid: Int32) -> Int32? {
        let g = getpgid(pid)
        return g > 0 ? g : nil
    }
}

public enum SpawnError: Error, CustomStringConvertible {
    case failed(String)
    public var description: String { if case .failed(let m) = self { return m }; return "" }
}

public enum Spawner {

    /// Moves a previous log to `<log>.1`, then spawns the plan in its own session with
    /// stdin on /dev/null and stdout and stderr on the log.
    public static func spawn(_ plan: LaunchPlan, log: URL) throws -> Int32 {
        let fm = FileManager.default
        // Servers print tokens and keys to their logs often enough that only the user may read them.
        try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: log.deletingLastPathComponent().path)
        let rotated = URL(fileURLWithPath: log.path + ".1")
        if fm.fileExists(atPath: log.path) {
            try? fm.removeItem(at: rotated)
            try fm.moveItem(at: log, to: rotated)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rotated.path)
        }

        var actions = Platform.blankFileActions
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)

        var attr = Platform.blankSpawnAttributes
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // posix_spawn inherits the caller's blocked and ignored signals; a test runner or app that
        // blocks SIGTERM would hand that to the server, and every stop would wait for SIGKILL.
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attr, &none)
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attr, &all)
        posix_spawnattr_setflags(&attr, Int16(Platform.spawnNewSession | Int32(POSIX_SPAWN_SETSIGMASK) | Int32(POSIX_SPAWN_SETSIGDEF)))

        let argv = plan.argv.map { strdup($0) } + [nil]
        let envp = plan.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, plan.executable, &actions, &attr, argv, envp)
        guard rc == 0 else {
            throw SpawnError.failed("posix_spawn: \(String(cString: strerror(rc)))")
        }
        return pid
    }
}

public enum Terminator {
    /// SIGTERM to the process group, then wait for `port` to stop listening; SIGKILL after `grace`.
    /// The group is signaled when `pid` leads it or when the caller names it (a group the app
    /// started, whose leader is a wrapper such as npm); otherwise `pid` is signaled alone, so a
    /// server sharing a group with a shell or another tool does not take them down.
    /// Returns true when the port ended up free.
    public static func stop(
        pid: Int32,
        port: Int,
        group: Int32? = nil,
        grace: TimeInterval = 5,
        poll: TimeInterval = 0.2,
        listeners: () -> [Listener] = { Platform.listeners() }
    ) -> Bool {
        guard pid > 1 else { return false }
        let signal = { (sig: Int32) in
            if let group, group > 1 { killpg(group, sig) } else { Terminator.signal(pid, sig) }
        }
        signal(SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if !listeners().contains(where: { $0.port == port && $0.pid == pid }) { return true }
            Thread.sleep(forTimeInterval: poll)
        }
        signal(SIGKILL)
        Thread.sleep(forTimeInterval: 0.3)
        return !listeners().contains(where: { $0.port == port })
    }

    static func signal(_ pid: Int32, _ sig: Int32) {
        if getpgid(pid) == pid {
            killpg(pid, sig)
        } else {
            kill(pid, sig)
        }
    }
}
