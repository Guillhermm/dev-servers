import Foundation

public struct ProcessFacts: Equatable {
    public let uid: UInt32
    public let cwd: String?

    public init(uid: UInt32, cwd: String?) {
        self.uid = uid
        self.cwd = cwd
    }
}

public enum StopDecision: Equatable {
    case allow(pid: Int32)
    case needsConfirmation(pid: Int32, command: String)
    case refuse(reason: String)
}

public enum StopPolicy {
    /// Decides what may be signaled for `entry`. Only listeners on the entry's own port count.
    /// A process the app started, or one running from inside the entry's path, is allowed;
    /// any other process owned by the user needs the user's confirmation.
    public static func decide(
        entry: RegistryEntry,
        registry: [RegistryEntry],
        listeners: [Listener],
        facts: [Int32: ProcessFacts],
        currentUID: UInt32,
        startedPIDs: Set<Int32>
    ) -> StopDecision {
        guard registry.contains(where: { $0.id == entry.id && $0.port == entry.port }) else {
            return .refuse(reason: "port \(entry.port) is not registered for \(entry.id)")
        }
        guard entry.managed else { return .refuse(reason: "\(entry.name) is not managed by this app") }

        let onPort = listeners.filter { $0.port == entry.port }
        guard !onPort.isEmpty else { return .refuse(reason: "nothing is listening on port \(entry.port)") }

        var pending: StopDecision?
        var firstAllowed: Int32?
        for l in onPort {
            guard l.pid > 1 else { return .refuse(reason: "refusing pid \(l.pid)") }
            guard let f = facts[l.pid] else {
                return .refuse(reason: "cannot inspect pid \(l.pid)")
            }
            guard f.uid == currentUID else {
                return .refuse(reason: "pid \(l.pid) belongs to another user")
            }
            if startedPIDs.contains(l.pid) || isInside(f.cwd, path: entry.path) {
                firstAllowed = firstAllowed ?? l.pid
            } else if pending == nil {
                pending = .needsConfirmation(pid: l.pid, command: l.command)
            }
        }
        if let pending { return pending }
        return .allow(pid: firstAllowed!)
    }

    static func isInside(_ cwd: String?, path: String) -> Bool {
        guard let cwd else { return false }
        let c = (cwd as NSString).standardizingPath
        let p = (path as NSString).standardizingPath
        return c == p || c.hasPrefix(p + "/")
    }
}
