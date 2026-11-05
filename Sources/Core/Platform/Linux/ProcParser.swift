import Foundation

/// A row of /proc/net/tcp or /proc/net/tcp6.
public struct ProcNetSocket: Equatable {
    public let address: String
    public let port: Int
    public let uid: UInt32
    public let inode: UInt64
}

/// Pure parsing of the /proc files the Linux platform reads, compiled on every platform so its
/// tests run anywhere.
public enum ProcParser {
    static let listenState = "0A"

    /// Rows in LISTEN state. Columns: sl, local, remote, st, tx:rx, tr:when, retrnsmt, uid, timeout, inode.
    public static func listening(_ text: String) -> [ProcNetSocket] {
        text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let f = line.split(whereSeparator: \.isWhitespace)
            guard f.count >= 10, f[3] == listenState else { return nil }
            let local = f[1].split(separator: ":")
            guard local.count == 2, let port = Int(local[1], radix: 16),
                  let address = address(hex: String(local[0])),
                  let uid = UInt32(f[7]), let inode = UInt64(f[9]) else { return nil }
            return ProcNetSocket(address: address, port: port, uid: uid, inode: inode)
        }
    }

    /// The kernel prints each 32-bit word in host order, which is little-endian on every
    /// architecture Dev Servers targets, so each word's bytes come out reversed.
    public static func address(hex: String) -> String? {
        guard hex.count == 8 || hex.count == 32 else { return nil }
        var bytes: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 8)
            guard let word = UInt32(hex[i..<j], radix: 16) else { return nil }
            bytes += [UInt8(word & 0xff), UInt8(word >> 8 & 0xff), UInt8(word >> 16 & 0xff), UInt8(word >> 24)]
            i = j
        }
        if bytes.count == 4 { return bytes.map(String.init).joined(separator: ".") }
        return ipv6(bytes)
    }

    /// RFC 5952 text form: lowercase, no leading zeros, the longest run of zero groups as `::`.
    static func ipv6(_ bytes: [UInt8]) -> String {
        let groups = stride(from: 0, to: 16, by: 2).map { Int(bytes[$0]) << 8 | Int(bytes[$0 + 1]) }
        var best = (start: -1, length: 0)
        var run = (start: -1, length: 0)
        for (k, g) in groups.enumerated() {
            if g == 0 {
                run = run.start < 0 ? (k, 1) : (run.start, run.length + 1)
                if run.length > best.length { best = run }
            } else {
                run = (-1, 0)
            }
        }
        let hex = groups.map { String($0, radix: 16) }
        guard best.length >= 2 else { return hex.joined(separator: ":") }
        let head = hex[..<best.start].joined(separator: ":")
        let tail = hex[(best.start + best.length)...].joined(separator: ":")
        return head + "::" + tail
    }

    /// `socket:[12345]` (the target of a /proc/<pid>/fd link) to 12345.
    public static func socketInode(link: String) -> UInt64? {
        guard link.hasPrefix("socket:["), link.hasSuffix("]") else { return nil }
        return UInt64(link.dropFirst(8).dropLast())
    }

    /// The real uid from /proc/<pid>/status (`Uid:` real, effective, saved, filesystem).
    public static func uid(status: String) -> UInt32? {
        for line in status.split(whereSeparator: \.isNewline) where line.hasPrefix("Uid:") {
            return line.split(whereSeparator: \.isWhitespace).dropFirst().first.flatMap { UInt32($0) }
        }
        return nil
    }
}
