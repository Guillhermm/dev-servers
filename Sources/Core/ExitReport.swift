#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// Why a process the app started has ended, in words the user can act on.
public struct ExitReport: Equatable {
    public let code: Int32?
    public let signal: Int32?

    /// Decodes a `waitpid` status (the WIFEXITED / WEXITSTATUS / WTERMSIG macros).
    public init(waitStatus status: Int32) {
        if status & 0x7f == 0 {
            code = (status >> 8) & 0xff
            signal = nil
        } else {
            code = nil
            signal = status & 0x7f
        }
    }

    public init(code: Int32?, signal: Int32?) {
        self.code = code
        self.signal = signal
    }

    public var reason: String {
        if let signal {
            let name = signal == SIGKILL ? "SIGKILL" : signal == SIGTERM ? "SIGTERM"
                : signal == SIGINT ? "SIGINT" : signal == SIGSEGV ? "SIGSEGV" : "signal \(signal)"
            return "killed by \(name)"
        }
        switch code ?? 0 {
        case 0: return "exited normally (code 0)"
        case 126: return "the command is not executable (exit 126)"
        case 127: return "command not found (exit 127); check that it is on the PATH of your login shell"
        case let c: return "exited with code \(c)"
        }
    }

    /// The last few non-empty lines of a log, newest last, for a one-glance hint at the cause.
    /// Reads only the end of the file, so a large log costs nothing.
    public static func tail(of file: URL, lines: Int = 3, maxBytes: Int = 8192) -> [String] {
        guard let text = readEnd(of: file, maxBytes: maxBytes) else { return [] }
        let kept = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return kept.suffix(lines).map { $0.count > 300 ? String($0.prefix(300)) + "…" : $0 }
    }

    public static func readEnd(of file: URL, maxBytes: Int) -> String? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd() else { return "" }
        var text = String(decoding: data, as: UTF8.self)
        // A cut in the middle of a line would show a fragment; drop it.
        if start > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        return text
    }
}
