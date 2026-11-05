import Foundation

/// Pure parsing, compiled on every platform so its tests run anywhere.
public enum LsofParser {
    /// Parses `lsof -F pcn` output: `p<pid>`, `c<command>`, then one `n<addr>:<port>` per socket.
    public static func parse(_ output: String) -> [Listener] {
        var result: [Listener] = []
        var pid: Int32?
        var command = ""
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = unescape(value)
            case "n":
                guard let pid, let (addr, port) = splitAddress(value) else { continue }
                result.append(Listener(pid: pid, command: command, port: port, address: addr))
            default:
                continue
            }
        }
        return result
    }

    /// Handles `*:8400`, `127.0.0.1:8400`, `[::1]:8400` and `[::]:8400`.
    static func splitAddress(_ s: String) -> (String, Int)? {
        let name = s.components(separatedBy: "->")[0]
        guard let colon = name.lastIndex(of: ":"),
              let port = Int(name[name.index(after: colon)...]) else { return nil }
        var addr = String(name[..<colon])
        if addr.hasPrefix("["), addr.hasSuffix("]") { addr = String(addr.dropFirst().dropLast()) }
        return (addr, port)
    }

    /// lsof escapes unprintable bytes in command names as `\xNN`.
    static func unescape(_ s: String) -> String {
        guard s.contains("\\x") else { return s }
        var bytes: [UInt8] = []
        let u = Array(s.utf8)
        var i = 0
        while i < u.count {
            if u[i] == 0x5C, i + 3 < u.count, u[i + 1] == 0x78,
               let b = UInt8(String(decoding: u[(i + 2)...(i + 3)], as: UTF8.self), radix: 16) {
                bytes.append(b)
                i += 4
            } else {
                bytes.append(u[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
