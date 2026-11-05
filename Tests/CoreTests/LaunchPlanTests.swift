import Testing
@testable import Core

@Suite struct LaunchPlanTests {
    private func entry(cwd: String = "/Users/t/p", start: [String] = ["npm", "run", "dev"],
                       env: [String: String] = [:]) -> RegistryEntry {
        RegistryEntry(id: "a", name: "A", path: "/Users/t/p", cwd: cwd, port: 8400, start: start, env: env)
    }

    @Test func argvUsesPositionalParameters() {
        let p = LaunchPlan(entry: entry(), baseEnvironment: [:])
        #expect(p.executable == "/bin/sh")
        #expect(p.argv == ["/bin/sh", "-c", "cd -- \"$1\" || exit 1; shift; exec \"$@\"", "dev-servers", "/Users/t/p", "npm", "run", "dev"])
    }

    @Test func hostileValuesStayInsideOneArgument() {
        let hostile = "/Users/t/$(rm -rf ~)"
        let arg = "; touch /tmp/pwned #"
        let p = LaunchPlan(entry: entry(cwd: hostile, start: ["tool", arg]), baseEnvironment: [:])
        #expect(p.argv[2] == LaunchPlan.script)
        #expect(!p.argv[2].contains("rm"))
        #expect(p.argv[4] == hostile)
        #expect(p.argv[6] == arg)
        #expect(p.argv.count == 7)
    }

    @Test func entryEnvOverridesBase() {
        let p = LaunchPlan(entry: entry(env: ["PORT": "8400", "A": "entry"]),
                           baseEnvironment: ["A": "base", "HOME": "/Users/t"])
        #expect(p.environment == ["PORT": "8400", "A": "entry", "HOME": "/Users/t"])
    }
}
