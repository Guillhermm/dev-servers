import Testing
@testable import Core

@Suite struct ListenerTableTests {
    @Test func parsesIPv4IPv6AndWildcard() {
        let out = """
        p101
        cpython3
        n127.0.0.1:8400
        p202
        cnode
        n*:3000
        n[::1]:3000
        p303
        cOllama
        n[::]:11434
        """
        let l = ListenerTable.parse(out)
        #expect(l == [
            Listener(pid: 101, command: "python3", port: 8400, address: "127.0.0.1"),
            Listener(pid: 202, command: "node", port: 3000, address: "*"),
            Listener(pid: 202, command: "node", port: 3000, address: "::1"),
            Listener(pid: 303, command: "Ollama", port: 11434, address: "::"),
        ])
    }

    @Test func multiplePidsOnOnePort() {
        let out = "p10\ncworker\nn*:9000\np11\ncworker\nn*:9000\n"
        let l = ListenerTable.parse(out)
        #expect(l.map(\.pid) == [10, 11])
        #expect(Set(l.map(\.port)) == [9000])
    }

    @Test func escapedCommandAndJunkLines() {
        let l = ListenerTable.parse("p5\ncGoogle\\x20Chrome\nfxx\nnbogus\nn*:1234\n\n")
        #expect(l == [Listener(pid: 5, command: "Google Chrome", port: 1234, address: "*")])
    }

    @Test func emptyOutput() {
        #expect(ListenerTable.parse("").isEmpty)
    }
}
