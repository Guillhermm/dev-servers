import Foundation

/// The registry argv is passed to zsh as positional parameters, never spliced into the script,
/// so a hostile cwd or argument cannot be interpreted as shell syntax.
public struct LaunchPlan: Equatable {
    public static let shell = "/bin/zsh"
    public static let script = "cd -- \"$1\" || exit 1; shift; exec \"$@\""

    public let executable: String
    /// Full argv, program name first.
    public let argv: [String]
    public let environment: [String: String]

    public init(entry: RegistryEntry, baseEnvironment: [String: String]) {
        executable = LaunchPlan.shell
        argv = [LaunchPlan.shell, "-lc", LaunchPlan.script, "_", entry.cwd] + entry.start
        environment = baseEnvironment.merging(entry.env) { _, entryValue in entryValue }
    }
}
