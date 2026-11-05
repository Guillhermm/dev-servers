import Foundation
import Testing
@testable import Core

private let home = "/Users/tester"

private func entryJSON(id: String = "alpha", port: Int = 8400, path: String = "/Users/tester/p",
                       cwd: String = "/Users/tester/p", start: String = #"["python3","-m","http.server"]"#,
                       extra: String = "") -> String {
    #"{"id":"\#(id)","name":"Alpha","path":"\#(path)","cwd":"\#(cwd)","port":\#(port),"start":\#(start)\#(extra)}"#
}

private func parse(_ entries: String...) throws -> [RegistryEntry] {
    try Registry.parse(Data("[\(entries.joined(separator: ","))]".utf8), home: home)
}

@Suite struct RegistryTests {
    @Test func goodEntryGetsDefaults() throws {
        let e = try parse(entryJSON())[0]
        #expect(e.managed == true)
        #expect(e.host == "127.0.0.1")
        #expect(e.url == "http://127.0.0.1:8400")
        #expect(e.env.isEmpty)
    }

    @Test func wrapperObjectIsAccepted() throws {
        let data = Data("{\"servers\":[\(entryJSON())]}".utf8)
        #expect(try Registry.parse(data, home: home).count == 1)
    }

    @Test func explicitUnmanagedAndUrl() throws {
        let e = try parse(entryJSON(extra: #","managed":false,"url":"http://localhost:8400/x""#))[0]
        #expect(e.managed == false)
        #expect(e.url == "http://localhost:8400/x")
    }

    @Test(arguments: ["Alpha", "a_b", "a b", "", "a/b", "ä"])
    func badIDRejected(id: String) {
        #expect(throws: RegistryError.invalidID(id)) { try parse(entryJSON(id: id)) }
    }

    @Test func duplicateIDRejected() {
        #expect(throws: RegistryError.duplicateID("alpha")) {
            try parse(entryJSON(), entryJSON(port: 8401))
        }
    }

    @Test(arguments: [0, 80, 1023, 65536, -1])
    func badPortRejected(port: Int) {
        #expect(throws: RegistryError.invalidPort(id: "alpha", port: port)) { try parse(entryJSON(port: port)) }
    }

    @Test func boundaryPortsAccepted() throws {
        _ = try parse(entryJSON(port: 1024), entryJSON(id: "b", port: 65535))
    }

    @Test func sharedPortIsAllowed() throws {
        #expect(try parse(entryJSON(), entryJSON(id: "b")).count == 2)
    }

    @Test func unmanagedMayLiveOutsideHome() throws {
        _ = try parse(entryJSON(path: "/opt/homebrew", cwd: "/opt/homebrew", extra: #","managed":false"#))
        #expect(throws: RegistryError.self) {
            try parse(entryJSON(path: "rel", cwd: "/opt/x", extra: #","managed":false"#))
        }
    }

    /// The user's own registry is gitignored, so a fresh clone has none to check.
    @Test func localRegistryLoadsWhenPresent() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let local = repo.appendingPathComponent("registry.json")
        guard FileManager.default.fileExists(atPath: local.path) else { return }
        #expect(!(try Registry.load(from: local)).isEmpty)
    }

    @Test(arguments: ["relative/path", "/etc", "/Users/tester", "/Users/tester/../other/x", "/Users/testerx/p", "~/p"])
    func badPathRejected(path: String) {
        #expect(throws: RegistryError.invalidPath(id: "alpha", field: "path", value: path)) {
            try parse(entryJSON(path: path))
        }
    }

    @Test func badCwdRejected() {
        #expect(throws: RegistryError.invalidPath(id: "alpha", field: "cwd", value: "/tmp")) {
            try parse(entryJSON(cwd: "/tmp"))
        }
    }

    @Test(arguments: ["[]", #"[""]"#])
    func emptyStartRejected(start: String) {
        #expect(throws: RegistryError.emptyStart("alpha")) { try parse(entryJSON(start: start)) }
    }

    @Test func startAsShellStringRejected() {
        #expect(throws: RegistryError.self) { try parse(entryJSON(start: #""npm run dev""#)) }
    }

    @Test func badEnvKeyRejected() {
        #expect(throws: RegistryError.invalidEnvKey(id: "alpha", key: "A=B")) {
            try parse(entryJSON(extra: #","env":{"A=B":"x"}"#))
        }
    }

    @Test func nonHttpURLRejected() {
        #expect(throws: RegistryError.invalidURL(id: "alpha", value: "file:///etc/passwd")) {
            try parse(entryJSON(extra: #","url":"file:///etc/passwd""#))
        }
    }

    @Test func missingKeyAndGarbageAreMalformed() {
        #expect(throws: RegistryError.self) { try Registry.parse(Data("[{\"id\":\"a\"}]".utf8), home: home) }
        #expect(throws: RegistryError.self) { try Registry.parse(Data("nope".utf8), home: home) }
    }

    @Test func shippedExampleIsValid() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("registry.example.json")
        let entries = try Registry.load(from: example, home: "/Users/you")
        #expect(entries.contains { !$0.managed })
    }
}

