import Foundation
import Testing
@testable import Core

@Suite struct UIAssetsTests {
    let root: URL
    let outside: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("uiassets-\(UUID().uuidString)")
        root = base.appendingPathComponent("ui")
        outside = base.appendingPathComponent("secret.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("<p>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("x".utf8).write(to: root.appendingPathComponent("app.js"))
        try Data("{}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.json"), withDestinationURL: outside)
    }

    @Test func servesFilesUnderRootWithTheirType() throws {
        let page = try #require(UIAssets.resolve(root: root, path: "/index.html"))
        #expect(page.mime == "text/html")
        #expect(UIAssets.resolve(root: root, path: "/app.js")?.mime == "text/javascript")
    }

    @Test func refusesEscapesMissingFilesAndDirectories() {
        #expect(UIAssets.resolve(root: root, path: "/../secret.json") == nil)
        #expect(UIAssets.resolve(root: root, path: "/%2e%2e/secret.json") == nil)
        #expect(UIAssets.resolve(root: root, path: "/link.json") == nil)
        #expect(UIAssets.resolve(root: root, path: "/missing.js") == nil)
        #expect(UIAssets.resolve(root: root, path: "/") == nil)
    }

    @Test func recognizesOnlyTheAppPage() {
        #expect(UIAssets.isPage(UIAssets.pageURL))
        #expect(!UIAssets.isPage(URL(string: "devservers://app/app.js")!))
        #expect(!UIAssets.isPage(URL(string: "devservers://evil/index.html")!))
        #expect(!UIAssets.isPage(URL(fileURLWithPath: "/tmp/index.html")))
    }
}
