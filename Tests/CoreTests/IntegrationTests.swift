import Darwin
import Foundation
import Testing
@testable import Core

private func freePort() -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = 0
    _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
    return Int(UInt16(bigEndian: addr.sin_port))
}

private func waitFor(_ timeout: TimeInterval = 20, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return cond()
}

@Suite(.serialized) struct IntegrationTests {
    @Test func spawnListenStopThroughServiceAndPolicy() throws {
        let home = NSHomeDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent(".dev-servers-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let port = freePort()
        let json = """
        [{"id":"it-http","name":"IT","path":"\(dir.path)","cwd":"\(dir.path)","port":\(port),
          "start":["python3","-m","http.server","\(port)","--bind","127.0.0.1"]}]
        """
        let reg = dir.appendingPathComponent("registry.json")
        try json.write(to: reg, atomically: true, encoding: .utf8)
        let logs = dir.appendingPathComponent("logs")

        let svc = Service(registryURL: reg, logDirectory: logs, grace: 5,
                          openURL: { _ in true }, openLog: { _ in true })

        let started = svc.handle(action: "start", id: "it-http") as! [String: Any]
        #expect(started["ok"] as? Bool == true)
        let pid = Int32(started["pid"] as! Int)
        defer { kill(pid, SIGKILL) }

        #expect(waitFor { ListenerProbe.current().contains { $0.port == port } })

        let status = (svc.handle(action: "status", id: nil) as! [[String: Any]])[0]
        #expect(status["listening"] as? Bool == true)
        #expect(status["ownedByApp"] as? Bool == true)
        #expect(status["pid"] as? Int == Int(pid))

        let again = svc.handle(action: "start", id: "it-http") as! [String: Any]
        #expect(again["ok"] as? Bool == false)

        let log = svc.handle(action: "log", id: "it-http") as! [String: Any]
        #expect(log["ok"] as? Bool == true)

        // SIGTERM alone frees the port; reaching the 5 s SIGKILL means the server ignored it.
        let t0 = Date()
        let stopped = svc.handle(action: "stop", id: "it-http") as! [String: Any]
        #expect(stopped["ok"] as? Bool == true)
        #expect(Date().timeIntervalSince(t0) < 2)
        #expect(waitFor { !ListenerProbe.current().contains { $0.port == port } })
    }

    @Test func foreignListenerNeedsConfirmationThenStops() throws {
        let home = NSHomeDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent(".dev-servers-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let port = freePort()
        let json = """
        [{"id":"foreign","name":"F","path":"\(dir.path)","cwd":"\(dir.path)","port":\(port),"start":["true"]}]
        """
        let reg = dir.appendingPathComponent("registry.json")
        try json.write(to: reg, atomically: true, encoding: .utf8)

        // Started outside the app and outside the entry's path.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "-m", "http.server", "\(port)", "--bind", "127.0.0.1"]
        p.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        defer { p.terminate() }
        #expect(waitFor { ListenerProbe.current().contains { $0.port == port } })

        let svc = Service(registryURL: reg, logDirectory: dir.appendingPathComponent("logs"), grace: 5,
                          openURL: { _ in true }, openLog: { _ in true })
        let first = svc.handle(action: "stop", id: "foreign") as! [String: Any]
        #expect(first["needsConfirmation"] as? Bool == true)
        let pid = first["pid"] as! Int

        let wrong = svc.handle(action: "confirmStop", id: "foreign", pid: Int32(pid + 1)) as! [String: Any]
        #expect(wrong["ok"] as? Bool == false)

        let ok = svc.handle(action: "confirmStop", id: "foreign", pid: Int32(pid)) as! [String: Any]
        #expect(ok["ok"] as? Bool == true)
        #expect(waitFor { !ListenerProbe.current().contains { $0.port == port } })
    }

    @Test func serverBehindAWrapperIsOwnedAndStoppedWithItsGroup() throws {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dev-servers-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let elsewhere = dir.deletingLastPathComponent().appendingPathComponent(dir.lastPathComponent + "-cwd")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: elsewhere) }

        let port = freePort()
        // The trailing `; :` keeps sh from exec'ing python, as npm run keeps node as its child.
        let json = """
        [{"id":"wrapped","name":"W","path":"\(dir.path)","cwd":"\(elsewhere.path)","port":\(port),
          "start":["/bin/sh","-c","python3 -m http.server \(port) --bind 127.0.0.1; :"]}]
        """
        let reg = dir.appendingPathComponent("registry.json")
        try json.write(to: reg, atomically: true, encoding: .utf8)
        let svc = Service(registryURL: reg, logDirectory: dir.appendingPathComponent("logs"), grace: 5,
                          openURL: { _ in true }, openLog: { _ in true })

        let started = svc.handle(action: "start", id: "wrapped") as! [String: Any]
        try #require(started["ok"] as? Bool == true, "\(started)")
        let wrapper = Int32(started["pid"] as! Int)
        defer { killpg(wrapper, SIGKILL) }
        #expect(waitFor { ListenerProbe.current().contains { $0.port == port } })

        let status = (svc.handle(action: "status", id: nil) as! [[String: Any]])[0]
        #expect(status["pid"] as? Int != Int(wrapper))
        #expect(status["ownedByApp"] as? Bool == true)

        // cwd is outside the entry's path, so only group ownership lets this through unconfirmed.
        let stopped = svc.handle(action: "stop", id: "wrapped") as! [String: Any]
        #expect(stopped["ok"] as? Bool == true)
        #expect(waitFor(5) { kill(wrapper, 0) == -1 && errno == ESRCH })
    }

    @Test func confirmStopWithoutPidIsRefused() throws {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dev-servers-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let port = 8400
        let reg = dir.appendingPathComponent("registry.json")
        try #"[{"id":"a","name":"A","path":"\#(dir.path)","cwd":"\#(dir.path)","port":\#(port),"start":["true"]}]"#
            .write(to: reg, atomically: true, encoding: .utf8)
        let victim = Process()
        victim.executableURL = URL(fileURLWithPath: "/bin/sleep")
        victim.arguments = ["30"]
        victim.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        try victim.run()
        defer { victim.terminate() }
        let pid = victim.processIdentifier
        let svc = Service(registryURL: reg, logDirectory: dir, grace: 0.2,
                          listeners: { [Listener(pid: pid, command: "sleep", port: port, address: "*")] },
                          openURL: { _ in true }, openLog: { _ in true })
        let reply = svc.handle(action: "confirmStop", id: "a", pid: nil) as! [String: Any]
        #expect(reply["ok"] as? Bool == false)
        #expect(victim.isRunning)
    }

    @Test func missingCwdDoesNotRunTheCommand() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dev-servers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("ran")
        let entry = RegistryEntry(id: "x", name: "X", path: dir.path, cwd: dir.appendingPathComponent("gone").path,
                                  port: 8400, start: ["/usr/bin/touch", marker.path])
        let pid = try Spawner.spawn(LaunchPlan(entry: entry, baseEnvironment: ProcessInfo.processInfo.environment),
                                    log: dir.appendingPathComponent("x.log"))
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        #expect(status != 0)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func unknownActionIdAndBrokenRegistry() throws {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dev-servers-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = dir.appendingPathComponent("registry.json")
        try #"[{"id":"a","name":"A","path":"\#(dir.path)","cwd":"\#(dir.path)","port":8499,"start":["true"]}]"#
            .write(to: reg, atomically: true, encoding: .utf8)
        let svc = Service(registryURL: reg, logDirectory: dir, openURL: { _ in true }, openLog: { _ in true })

        #expect((svc.handle(action: "explode", id: "a") as! [String: Any])["ok"] as? Bool == false)
        #expect((svc.handle(action: "start", id: "nope") as! [String: Any])["ok"] as? Bool == false)
        #expect((svc.handle(action: "start", id: nil) as! [String: Any])["ok"] as? Bool == false)
        #expect((svc.handle(action: "log", id: "a") as! [String: Any])["ok"] as? Bool == false)
        #expect((svc.handle(action: "list", id: nil) as! [[String: Any]]).count == 1)

        try "[]x".write(to: reg, atomically: true, encoding: .utf8)
        #expect(svc.reload() != nil)
        #expect((svc.handle(action: "list", id: nil) as! [String: Any])["ok"] as? Bool == false)
    }
}
