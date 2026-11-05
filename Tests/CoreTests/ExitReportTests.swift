import Darwin
import Foundation
import Testing
@testable import Core

@Suite struct ExitReportTests {
    @Test func decodesWaitStatus() {
        #expect(ExitReport(waitStatus: 127 << 8) == ExitReport(code: 127, signal: nil))
        #expect(ExitReport(waitStatus: 0) == ExitReport(code: 0, signal: nil))
        #expect(ExitReport(waitStatus: SIGKILL) == ExitReport(code: nil, signal: SIGKILL))
    }

    @Test func reasonsNameTheLikelyCause() {
        #expect(ExitReport(code: 127, signal: nil).reason.contains("command not found"))
        #expect(ExitReport(code: 126, signal: nil).reason.contains("not executable"))
        #expect(ExitReport(code: 1, signal: nil).reason == "exited with code 1")
        #expect(ExitReport(code: nil, signal: SIGTERM).reason == "killed by SIGTERM")
    }

    @Test func tailKeepsLastNonEmptyLines() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tail-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: file) }
        try "one\n\ntwo\nthree\n   \nfour\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(ExitReport.tail(of: file) == ["two", "three", "four"])
        #expect(ExitReport.tail(of: file.appendingPathExtension("missing")) == [])
    }

    @Test func readEndDropsThePartialFirstLine() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tail-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: file) }
        try (String(repeating: "x", count: 100) + "\nlast line\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(ExitReport.readEnd(of: file, maxBytes: 20) == "last line\n")
    }
}
