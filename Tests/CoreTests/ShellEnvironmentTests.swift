import Foundation
import Testing
@testable import Core

@Suite struct ShellEnvironmentTests {
    private func output(_ noise: String, _ records: [String], close: Bool = true) -> Data {
        var d = Data(noise.utf8)
        d.append(Data(ShellEnvironment.marker.utf8))
        for r in records { d.append(Data(r.utf8)); d.append(0) }
        if close { d.append(Data(ShellEnvironment.marker.utf8)) }
        d.append(Data("trailing noise".utf8))
        return d
    }

    @Test func parsesRecordsBetweenMarkersOnly() {
        let env = ShellEnvironment.parse(output("motd = banner\n", ["PATH=/a:/b", "MULTI=line1\nline2", "EQ=a=b"]))
        #expect(env == ["PATH": "/a:/b", "MULTI": "line1\nline2", "EQ": "a=b"])
    }

    @Test func missingMarkerIsNil() {
        #expect(ShellEnvironment.parse(Data("zsh: error".utf8)) == nil)
        #expect(ShellEnvironment.parse(output("", ["A=1"], close: false)) == nil)
    }

    @Test func commandIsInteractiveLogin() {
        #expect(Array(ShellEnvironment.command(shell: "/bin/zsh").prefix(2)) == ["/bin/zsh", "-ilc"])
    }

    @Test func readsTheInteractiveRcFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shellenv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "echo noise from rc\nexport DEV_SERVERS_PROBE=from-zshrc\n"
            .write(to: dir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let env = ShellEnvironment.resolve(shell: "/bin/zsh", timeout: 10,
                                           fallback: ["HOME": dir.path, "ZDOTDIR": dir.path, "PATH": "/usr/bin:/bin"])
        #expect(env["DEV_SERVERS_PROBE"] == "from-zshrc")
    }

    @Test func hangingShellFallsBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shellenv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("slow-shell")
        try "#!/bin/sh\nexec sleep 30\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let t0 = Date()
        let env = ShellEnvironment.resolve(shell: fake.path, timeout: 0.5, fallback: ["ONLY": "fallback"])
        #expect(env == ["ONLY": "fallback"])
        #expect(Date().timeIntervalSince(t0) < 5)
    }

    @Test func missingShellFallsBack() {
        #expect(ShellEnvironment.resolve(shell: "/nonexistent/shell", fallback: ["A": "1"]) == ["A": "1"])
    }
}
