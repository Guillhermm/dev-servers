import Foundation

/// The bridge logic without any UI framework: the app target only forwards messages and
/// supplies the two openers.
public final class Service: @unchecked Sendable {
    public typealias Opener = (URL) -> Bool

    private let lock = NSLock()
    private var entries: [RegistryEntry] = []
    private var loadError: String?
    private var started = Set<Int32>()

    private let registryURL: URL
    private let logDirectory: URL
    private let home: String
    private let uid: UInt32
    private let listeners: () -> [Listener]
    private let groupOf: (Int32) -> Int32?
    private let openURL: Opener
    private let openLog: Opener
    private let grace: TimeInterval

    public init(
        registryURL: URL,
        logDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/Dev Servers"),
        home: String = NSHomeDirectory(),
        uid: UInt32 = getuid(),
        grace: TimeInterval = 5,
        listeners: @escaping () -> [Listener] = { ListenerProbe.current() },
        groupOf: @escaping (Int32) -> Int32? = ProcessProbe.group(of:),
        openURL: @escaping Opener,
        openLog: @escaping Opener
    ) {
        self.registryURL = registryURL
        self.logDirectory = logDirectory
        self.home = home
        self.uid = uid
        self.grace = grace
        self.listeners = listeners
        self.groupOf = groupOf
        self.openURL = openURL
        self.openLog = openLog
        reload()
    }

    /// Returns the load error, if any, so the caller can show it.
    @discardableResult
    public func reload() -> String? {
        lock.lock(); defer { lock.unlock() }
        do {
            entries = try Registry.load(from: registryURL, home: home)
            loadError = nil
        } catch {
            entries = []
            loadError = "\(error)"
        }
        return loadError
    }

    /// Dispatches one bridge message. The result is plain JSON types, so WebKit can hand it to
    /// the page without Swift ever composing script text.
    public func handle(action: String?, id: String?, pid: Int32? = nil) -> Any {
        lock.lock()
        let snapshot = entries
        let err = loadError
        lock.unlock()

        guard let action else { return failure("missing action") }
        if let err { return failure(err) }

        if action == "list" { return snapshot.map(Self.describe) }
        if action == "status" { return status(snapshot) }

        let known: Set<String> = ["start", "stop", "confirmStop", "open", "log"]
        guard known.contains(action) else { return failure("unknown action '\(action)'") }
        guard let id, let entry = snapshot.first(where: { $0.id == id }) else {
            return failure("unknown id '\(id ?? "")'")
        }
        switch action {
        case "start": return start(entry)
        case "stop": return stop(entry, snapshot, confirmed: false, expectedPID: nil)
        case "confirmStop": return stop(entry, snapshot, confirmed: true, expectedPID: pid)
        case "open":
            guard let url = URL(string: entry.url) else { return failure("bad url") }
            if openURL(url) { return success() }
            return failure("could not open \(entry.url)")
        default:
            let log = logURL(entry)
            guard FileManager.default.fileExists(atPath: log.path) else { return failure("no log yet for \(entry.id)") }
            if openLog(log) { return success() }
            return failure("could not open the log")
        }
    }

    public func logURL(_ entry: RegistryEntry) -> URL {
        logDirectory.appendingPathComponent("\(entry.id).log")
    }

    private func success() -> [String: Any] { ["ok": true] }
    private func failure(_ message: String) -> [String: Any] { ["ok": false, "error": message] }

    static func describe(_ e: RegistryEntry) -> [String: Any] {
        ["id": e.id, "name": e.name, "port": e.port, "url": e.url, "managed": e.managed, "notes": e.notes]
    }

    private func ownedPIDs() -> Set<Int32> {
        lock.lock(); defer { lock.unlock() }
        started = started.filter(ProcessProbe.isAlive)
        return started
    }

    /// The app-started group a listener belongs to. Every start gets its own session, so a server
    /// behind a wrapper (npm run dev -> node) shares the group of the pid the app spawned.
    private func ownerGroup(_ pid: Int32, _ owned: Set<Int32>) -> Int32? {
        if owned.contains(pid) { return pid }
        guard let g = groupOf(pid), owned.contains(g) else { return nil }
        return g
    }

    private func status(_ snapshot: [RegistryEntry]) -> [[String: Any]] {
        let table = listeners()
        let owned = ownedPIDs()
        return snapshot.map { e in
            guard let l = table.filter({ $0.port == e.port }).min(by: { $0.pid < $1.pid }) else {
                return ["id": e.id, "listening": false, "pid": NSNull(), "command": NSNull(), "ownedByApp": false]
            }
            return ["id": e.id, "listening": true, "pid": Int(l.pid), "command": l.command,
                    "ownedByApp": ownerGroup(l.pid, owned) != nil]
        }
    }

    private func start(_ e: RegistryEntry) -> [String: Any] {
        guard e.managed else { return failure("\(e.name) is not managed by this app") }
        if listeners().contains(where: { $0.port == e.port }) {
            return failure("port \(e.port) is already in use")
        }
        let plan = LaunchPlan(entry: e, baseEnvironment: ProcessInfo.processInfo.environment)
        do {
            let pid = try Spawner.spawn(plan, log: logURL(e))
            lock.lock(); started.insert(pid); lock.unlock()
            reapWhenDone(pid)
            return ["ok": true, "pid": Int(pid)]
        } catch {
            return failure("\(error)")
        }
    }

    private func stop(_ e: RegistryEntry, _ registry: [RegistryEntry], confirmed: Bool,
                      expectedPID: Int32?) -> [String: Any] {
        let table = listeners()
        let onPort = table.filter { $0.port == e.port }
        var facts: [Int32: ProcessFacts] = [:]
        for l in onPort { facts[l.pid] = ProcessProbe.facts(pid: l.pid) }
        let owned = ownedPIDs()
        let startedHere = Set(onPort.map(\.pid).filter { ownerGroup($0, owned) != nil })

        let decision = StopPolicy.decide(
            entry: e, registry: registry, listeners: table, facts: facts,
            currentUID: uid, startedPIDs: startedHere)

        switch decision {
        case .refuse(let reason):
            return failure(reason)
        case .needsConfirmation(let pid, let command):
            guard confirmed else {
                return ["ok": false, "needsConfirmation": true, "pid": Int(pid), "command": command]
            }
            guard expectedPID == pid else {
                return failure("the listener on port \(e.port) changed; stop again")
            }
            return terminate(pid, e, group: nil)
        case .allow(let pid):
            return terminate(pid, e, group: ownerGroup(pid, owned))
        }
    }

    /// Without this the spawned child stays a zombie until the app quits. The pid leaves the
    /// started set as it is reaped, so a later process reusing it is never taken for the app's.
    private func reapWhenDone(_ pid: Int32) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            guard let self else { return }
            self.lock.lock(); self.started.remove(pid); self.lock.unlock()
        }
    }

    private func terminate(_ pid: Int32, _ e: RegistryEntry, group: Int32?) -> [String: Any] {
        let freed = Terminator.stop(pid: pid, port: e.port, group: group, grace: grace, listeners: listeners)
        return freed ? ["ok": true, "pid": Int(pid)] : failure("port \(e.port) is still in use after SIGKILL")
    }
}
