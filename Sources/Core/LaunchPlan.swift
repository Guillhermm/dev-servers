import Foundation

/// The registry argv is passed to sh as positional parameters, never spliced into the script,
/// so a hostile cwd or argument cannot be interpreted as shell syntax. No login or rc files run
/// here: the base environment already comes from the user's shell (see ShellEnvironment).
public struct LaunchPlan: Equatable {
    public static let shell = "/bin/sh"
    public static let script = "cd -- \"$1\" || exit 1; shift; exec \"$@\""

    public let executable: String
    /// Full argv, program name first.
    public let argv: [String]
    public let environment: [String: String]

    public init(entry: RegistryEntry, baseEnvironment: [String: String]) {
        executable = LaunchPlan.shell
        argv = [LaunchPlan.shell, "-c", LaunchPlan.script, "_", entry.cwd] + entry.start
        environment = baseEnvironment.merging(entry.env) { _, entryValue in entryValue }
    }
}
