import Testing
@testable import Core

@Suite struct StopPolicyTests {
    let me: UInt32 = 501
    let entry = RegistryEntry(id: "a", name: "A", path: "/Users/t/p", cwd: "/Users/t/p", port: 8400, start: ["x"])
    var registry: [RegistryEntry] { [entry] }

    private func decide(_ e: RegistryEntry? = nil, listeners: [Listener], facts: [Int32: ProcessFacts],
                        started: Set<Int32> = []) -> StopDecision {
        StopPolicy.decide(entry: e ?? entry, registry: registry, listeners: listeners, facts: facts,
                          currentUID: me, startedPIDs: started)
    }

    private func l(_ pid: Int32, port: Int = 8400, cmd: String = "node") -> Listener {
        Listener(pid: pid, command: cmd, port: port, address: "*")
    }

    @Test func startedByAppIsAllowed() {
        #expect(decide(listeners: [l(500)], facts: [500: .init(uid: me, cwd: "/elsewhere")], started: [500])
                == .allow(pid: 500))
    }

    @Test func cwdInsideEntryPathIsAllowed() {
        #expect(decide(listeners: [l(500)], facts: [500: .init(uid: me, cwd: "/Users/t/p/sub")]) == .allow(pid: 500))
        #expect(decide(listeners: [l(500)], facts: [500: .init(uid: me, cwd: "/Users/t/p")]) == .allow(pid: 500))
    }

    @Test func siblingDirectoryPrefixIsNotInside() {
        #expect(decide(listeners: [l(500)], facts: [500: .init(uid: me, cwd: "/Users/t/p-other")])
                == .needsConfirmation(pid: 500, command: "node"))
    }

    @Test func foreignProcessNeedsConfirmation() {
        #expect(decide(listeners: [l(500, cmd: "python3")], facts: [500: .init(uid: me, cwd: "/tmp")])
                == .needsConfirmation(pid: 500, command: "python3"))
        #expect(decide(listeners: [l(500)], facts: [500: .init(uid: me, cwd: nil)])
                == .needsConfirmation(pid: 500, command: "node"))
    }

    @Test func uidMismatchRefused() {
        guard case .refuse = decide(listeners: [l(500)], facts: [500: .init(uid: 0, cwd: "/Users/t/p")], started: [500])
        else { Issue.record("expected refuse"); return }
    }

    @Test(arguments: [Int32(0), 1, -3])
    func lowPidsRefused(pid: Int32) {
        guard case .refuse = decide(listeners: [l(pid)], facts: [pid: .init(uid: me, cwd: "/Users/t/p")], started: [pid])
        else { Issue.record("expected refuse"); return }
    }

    @Test func unmanagedRefused() {
        let e = RegistryEntry(id: "a", name: "A", path: "/Users/t/p", cwd: "/Users/t/p", port: 8400,
                              start: ["x"], managed: false)
        guard case .refuse = StopPolicy.decide(entry: e, registry: [e], listeners: [l(500)],
                                               facts: [500: .init(uid: me, cwd: "/Users/t/p")],
                                               currentUID: me, startedPIDs: [500])
        else { Issue.record("expected refuse"); return }
    }

    @Test func entryNotInRegistryRefused() {
        guard case .refuse = StopPolicy.decide(entry: entry, registry: [], listeners: [l(500)],
                                               facts: [500: .init(uid: me, cwd: "/Users/t/p")],
                                               currentUID: me, startedPIDs: [500])
        else { Issue.record("expected refuse"); return }
    }

    @Test func listenerOnOtherPortIsIgnored() {
        guard case .refuse = decide(listeners: [l(500, port: 9999)], facts: [500: .init(uid: me, cwd: "/Users/t/p")])
        else { Issue.record("expected refuse"); return }
    }

    @Test func uninspectableProcessRefused() {
        guard case .refuse = decide(listeners: [l(500)], facts: [:]) else { Issue.record("expected refuse"); return }
    }

    @Test func mixedPidsRequireConfirmationForTheForeignOne() {
        let d = decide(listeners: [l(500), l(501, cmd: "other")],
                       facts: [500: .init(uid: me, cwd: "/Users/t/p"), 501: .init(uid: me, cwd: "/tmp")])
        #expect(d == .needsConfirmation(pid: 501, command: "other"))
    }

    @Test func sharedPortStopsOnlyTheEntryWhoseTreeOwnsTheListener() {
        let other = RegistryEntry(id: "b", name: "B", path: "/Users/t/q", cwd: "/Users/t/q", port: 8400, start: ["x"])
        let facts: [Int32: ProcessFacts] = [500: ProcessFacts(uid: me, cwd: "/Users/t/q/web")]
        let reg = [entry, other]
        let forA = StopPolicy.decide(entry: entry, registry: reg, listeners: [l(500)], facts: facts,
                                     currentUID: me, startedPIDs: [])
        let forB = StopPolicy.decide(entry: other, registry: reg, listeners: [l(500)], facts: facts,
                                     currentUID: me, startedPIDs: [])
        #expect(forA == .needsConfirmation(pid: 500, command: "node"))
        #expect(forB == .allow(pid: 500))
    }
}
