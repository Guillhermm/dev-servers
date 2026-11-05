import Foundation

/// A TCP socket in LISTEN state, as the platform reports it.
public struct Listener: Equatable {
    public let pid: Int32
    public let command: String
    public let port: Int
    public let address: String

    public init(pid: Int32, command: String, port: Int, address: String) {
        self.pid = pid
        self.command = command
        self.port = port
        self.address = address
    }
}
