#if os(macOS)
import Darwin
import Foundation

extension Platform {
    public static let name = "macOS"
    public static let defaultShell = "/bin/zsh"
    public static let spawnNewSession = Int32(POSIX_SPAWN_SETSID)
    public typealias FileActions = posix_spawn_file_actions_t?
    public typealias SpawnAttributes = posix_spawnattr_t?
    static var blankFileActions: FileActions { nil }
    static var blankSpawnAttributes: SpawnAttributes { nil }

    public static let logDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Dev Servers")

    static let lsofPath = "/usr/sbin/lsof"

    /// One lsof call for every TCP listener owned by the user.
    public static func listeners(uid: uid_t = getuid()) -> [Listener] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: lsofPath)
        p.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", String(uid), "-F", "pcn"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return LsofParser.parse(String(decoding: data, as: UTF8.self))
    }

    public static func processFacts(pid: Int32) -> ProcessFacts? {
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return nil }

        var vnode = proc_vnodepathinfo()
        let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        var cwd: String?
        if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vnodeSize) == vnodeSize {
            cwd = withUnsafePointer(to: &vnode.pvi_cdir.vip_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
        }
        return ProcessFacts(uid: bsd.pbi_uid, cwd: cwd)
    }
}
#endif
