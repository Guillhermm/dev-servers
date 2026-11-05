import Foundation

/// The environment a terminal would give the user. An app opened from Finder gets launchd's bare
/// PATH, and tools installed through nvm, pyenv, asdf and the like are only added by the shell's
/// interactive startup files, so a login shell alone (`zsh -l`) still cannot find `npm`.
public enum ShellEnvironment {
    static let marker = "__DEV_SERVERS_ENV_7f3a__"

    /// The argv that prints the environment between two markers, so anything the startup files
    /// print on their own is ignored.
    public static func command(shell: String) -> [String] {
        [shell, "-ilc", "printf '%s' \(marker); /usr/bin/env -0; printf '%s' \(marker)"]
    }

    /// nil when the markers are missing, which means the shell failed before reaching `env`.
    public static func parse(_ output: Data) -> [String: String]? {
        let m = Data(marker.utf8)
        guard let open = output.range(of: m),
              let close = output.range(of: m, in: open.upperBound..<output.endIndex) else { return nil }
        var env: [String: String] = [:]
        for record in output[open.upperBound..<close.lowerBound].split(separator: 0) {
            guard let text = String(data: Data(record), encoding: .utf8),
                  let eq = text.firstIndex(of: "="), eq != text.startIndex else { continue }
            env[String(text[..<eq])] = String(text[text.index(after: eq)...])
        }
        return env.isEmpty ? nil : env
    }

    /// Runs the user's shell once. Falls back to `fallback` when the shell is missing, hangs past
    /// `timeout` or prints nothing usable, so a broken rc file never blocks a start.
    public static func resolve(
        shell: String? = ProcessInfo.processInfo.environment["SHELL"],
        timeout: TimeInterval = 10,
        fallback: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let sh = (shell?.hasPrefix("/") == true) ? shell! : Platform.defaultShell
        let argv = command(shell: sh)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.environment = fallback
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        do { try p.run() } catch { return fallback }

        final class Output: @unchecked Sendable { var data = Data() }
        let output = Output()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue(label: "shell-env").async {
            output.data = out.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        // The semaphore orders the write above before this read.
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return fallback
        }
        p.waitUntilExit()
        return parse(output.data) ?? fallback
    }
}
