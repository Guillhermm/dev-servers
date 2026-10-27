import Foundation

public struct RegistryEntry: Codable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let cwd: String
    public let port: Int
    public let host: String
    public let start: [String]
    public let env: [String: String]
    public let url: String
    public let managed: Bool
    public let notes: String

    public init(id: String, name: String, path: String, cwd: String, port: Int,
                host: String = "127.0.0.1", start: [String], env: [String: String] = [:],
                url: String? = nil, managed: Bool = true,
                notes: String = "") {
        self.id = id
        self.name = name
        self.path = path
        self.cwd = cwd
        self.port = port
        self.host = host
        self.start = start
        self.env = env
        self.url = url ?? "http://\(host):\(port)"
        self.managed = managed
        self.notes = notes
    }

    private enum Keys: String, CodingKey {
        case id, name, path, cwd, port, host, start, env, url, managed, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let host = try c.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        let port = try c.decode(Int.self, forKey: .port)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            path: try c.decode(String.self, forKey: .path),
            cwd: try c.decode(String.self, forKey: .cwd),
            port: port,
            host: host,
            start: try c.decode([String].self, forKey: .start),
            env: try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:],
            url: try c.decodeIfPresent(String.self, forKey: .url),
            managed: try c.decodeIfPresent(Bool.self, forKey: .managed) ?? true,
            notes: try c.decodeIfPresent(String.self, forKey: .notes) ?? "")
    }
}

public enum RegistryError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case malformed(String)
    case invalidID(String)
    case duplicateID(String)
    case invalidPort(id: String, port: Int)
    case invalidPath(id: String, field: String, value: String)
    case emptyStart(String)
    case invalidEnvKey(id: String, key: String)
    case invalidURL(id: String, value: String)

    public var description: String {
        switch self {
        case .unreadable(let m): return "registry unreadable: \(m)"
        case .malformed(let m): return "registry malformed: \(m)"
        case .invalidID(let id): return "invalid id '\(id)' (must match ^[a-z0-9-]+$)"
        case .duplicateID(let id): return "duplicate id '\(id)'"
        case .invalidPort(let id, let p): return "\(id): port \(p) outside 1024-65535"
        case .invalidPath(let id, let f, let v): return "\(id): \(f) '\(v)' must be an absolute path (under the home directory when managed)"
        case .emptyStart(let id): return "\(id): start must be a non-empty argv array with a non-empty program"
        case .invalidEnvKey(let id, let k): return "\(id): invalid env name '\(k)'"
        case .invalidURL(let id, let v): return "\(id): url '\(v)' must be http or https"
        }
    }
}

public enum Registry {
    /// Accepts either a bare array of entries or `{"servers": [...]}`.
    public static func load(from fileURL: URL, home: String = NSHomeDirectory()) throws -> [RegistryEntry] {
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch {
            throw RegistryError.unreadable("\(fileURL.path): \(error.localizedDescription)")
        }
        return try parse(data, home: home)
    }

    public static func parse(_ data: Data, home: String = NSHomeDirectory()) throws -> [RegistryEntry] {
        struct Wrapper: Decodable { let servers: [RegistryEntry] }
        let decoder = JSONDecoder()
        let entries: [RegistryEntry]
        do {
            if let w = try? decoder.decode(Wrapper.self, from: data) {
                entries = w.servers
            } else {
                entries = try decoder.decode([RegistryEntry].self, from: data)
            }
        } catch {
            throw RegistryError.malformed(describe(error))
        }
        try validate(entries, home: home)
        return entries
    }

    public static func validate(_ entries: [RegistryEntry], home: String = NSHomeDirectory()) throws {
        var ids = Set<String>()
        for e in entries {
            guard e.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else {
                throw RegistryError.invalidID(e.id)
            }
            guard ids.insert(e.id).inserted else { throw RegistryError.duplicateID(e.id) }
            guard (1024...65535).contains(e.port) else {
                throw RegistryError.invalidPort(id: e.id, port: e.port)
            }
            for (field, value) in [("path", e.path), ("cwd", e.cwd)] where !(e.managed ? isUnderHome(value, home: home) : value.hasPrefix("/")) {
                throw RegistryError.invalidPath(id: e.id, field: field, value: value)
            }
            guard let program = e.start.first, !program.isEmpty else { throw RegistryError.emptyStart(e.id) }
            for k in e.env.keys where k.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) == nil {
                throw RegistryError.invalidEnvKey(id: e.id, key: k)
            }
            guard let u = URL(string: e.url), let s = u.scheme, s == "http" || s == "https", u.host != nil else {
                throw RegistryError.invalidURL(id: e.id, value: e.url)
            }
        }
    }

    static func isUnderHome(_ path: String, home: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let std = (path as NSString).standardizingPath
        let h = (home as NSString).standardizingPath
        return std.hasPrefix(h + "/") && std.count > h.count + 1
    }

    private static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        switch e {
        case .keyNotFound(let k, _): return "missing key '\(k.stringValue)'"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            let path = c.codingPath.map(\.stringValue).joined(separator: ".")
            return "\(c.debugDescription) at \(path)"
        @unknown default: return "\(e)"
        }
    }
}
