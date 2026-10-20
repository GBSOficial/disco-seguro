import Foundation
import Testing
@testable import DiscoCore

// Fixtures stay inside the repository. They are deliberately retained for inspection.
private func fixture() throws -> URL {
    let source = URL(fileURLWithPath: #filePath)
    let root = source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let home = root.appendingPathComponent(".build/test-homes/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}
private func directory(_ home: URL, _ path: String) throws -> URL {
    let url = home.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func file(_ parent: URL, _ name: String, bytes: Int = 8192) throws -> URL {
    let url = parent.appendingPathComponent(name)
    try Data(repeating: 42, count: bytes).write(to: url)
    return url
}
private final class FakeTrasher: Trasher {
    let home: URL
    var calls: [URL] = []
    init(home: URL) { self.home = home }
    func trash(_ url: URL) throws -> URL {
        calls.append(url)
        let root = try directory(home, ".Trash")
        let destination = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
    func restore(_ trashed: URL, to original: URL) throws { try FileManager.default.moveItem(at: trashed, to: original) }
}
@Test func pathBoundariesAndLinks() throws {
    let home = try fixture(), root = try directory(home, "Library/Caches/pip")
    let item = try file(root, "normal"), guarder = PathGuard(home: home)
    try guarder.validate(item, root: root)
    let documents = try directory(home, "Documents")
    let targetLink = home.appendingPathComponent("Library/Caches/linked")
    try FileManager.default.createSymbolicLink(at: targetLink, withDestinationURL: documents)
    #expect(throws: SafetyError.self) { try guarder.validate(targetLink, root: targetLink, allowRoot: true) }
    let link = root.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: documents)
    #expect(throws: SafetyError.self) { try guarder.validate(link, root: root) }
    let sibling = try directory(home, "Library/Caches2")
    #expect(throws: SafetyError.self) { try guarder.validate(sibling, root: home.appendingPathComponent("Library/Caches")) }
    #expect(throws: SafetyError.self) { try guarder.validate(root, root: root) }
    #expect(throws: SafetyError.self) { try guarder.validate(URL(fileURLWithPath: "/usr/test"), root: root) }
}
@Test func scannerIgnoresSymlink() throws {
    let home = try fixture(), root = try directory(home, "Library/Caches/pip")
    let documents = try directory(home, "Documents"), outside = try file(documents, "large", bytes: 1_048_576)
    let scanner = Scanner(home: home)
    let before = scanner.size(root)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
    #expect(scanner.size(root) == before)
    #expect(scanner.scan(Targets.fixed.first { $0.relativePath == "Library/Caches/pip" }!).items.isEmpty)
}
@Test func cleanerAndUndoJournal() throws {
    let home = try fixture(), root = try directory(home, "Library/Caches/pip")
    let nested = try directory(root, "nested"), a = try file(root, "a")
    _ = try file(nested, "b")
    let target = Targets.fixed.first { $0.relativePath == "Library/Caches/pip" }!
    let plan = Scanner(home: home).scan(target), fake = FakeTrasher(home: home)
    let journal = try Cleaner(home: home, trasher: fake).execute([plan], running: { [] })
    #expect(Set(fake.calls.map(\.path)) == Set([a.path, nested.path]))
    #expect(!fake.calls.contains(root))
    #expect(PathGuard.exists(root))
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: journal))
    #expect(manifest.items.count == 2)
    #expect(manifest.items.reduce(0) { $0 + $1.bytes } == plan.bytes)
    #expect(manifest.items.allSatisfy { PathGuard.exists(URL(fileURLWithPath: $0.naLixeira)) })
    let count = try Undo(home: home, trasher: fake).latest()
    #expect(count == 2)
    #expect(PathGuard.exists(a)); #expect(PathGuard.exists(nested.appendingPathComponent("b")))
    #expect(try Undo(home: home, trasher: fake).latest() == 0)
}
@Test func logsOnlyOldRegularFiles() throws {
    let home = try fixture(), root = try directory(home, "Library/Logs")
    let nested = try directory(root, "nested")
    let old = try file(nested, "old.log"), recent = try file(root, "recent.log")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86400)], ofItemAtPath: old.path)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("old-link"), withDestinationURL: old)
    let target = Targets.fixed.first { $0.logs }!, fake = FakeTrasher(home: home)
    let plan = Scanner(home: home).scan(target)
    #expect(plan.items.map(\.url) == [old])
    _ = try Cleaner(home: home, trasher: fake).execute([plan], running: { [] })
    #expect(fake.calls == [old]); #expect(PathGuard.exists(recent)); #expect(PathGuard.exists(nested))
}
@Test func ownerRecheckedAndUnknownTargetRejected() throws {
    let home = try fixture(), root = try directory(home, "Library/Caches/Google/Chrome")
    _ = try file(root, "cache")
    let target = Targets.fixed.first { $0.relativePath == "Library/Caches/Google/Chrome" }!
    let scanner = Scanner(home: home), fake = FakeTrasher(home: home)
    #expect(scanner.scan(target, running: ["com.google.Chrome"]).blocked != nil)
    #expect(throws: SafetyError.self) { _ = try Cleaner(home: home, trasher: fake).execute([scanner.scan(target)], running: { ["com.google.Chrome"] }) }
    let unknown = CacheTarget("Documents")
    #expect(throws: SafetyError.self) { _ = try Cleaner(home: home, trasher: fake).execute([scanner.scan(unknown)], running: { [] }) }
    #expect(fake.calls.isEmpty)
}
@Test func undoPreservesExistingOriginal() throws {
    let home = try fixture(), root = try directory(home, "Library/Caches/pip")
    let original = try file(root, "cache"), fake = FakeTrasher(home: home)
    let target = Targets.fixed.first { $0.relativePath == "Library/Caches/pip" }!
    _ = try Cleaner(home: home, trasher: fake).execute([Scanner(home: home).scan(target)], running: { [] })
    let replacement = Data("novo".utf8); try replacement.write(to: original)
    #expect(try Undo(home: home, trasher: fake).latest() == 0)
    #expect(try Data(contentsOf: original) == replacement)
}
@Test func dynamicAllowlistAndDefaultConfig() throws {
    let home = try fixture()
    _ = try directory(home, "Library/Caches/Example.ShipIt")
    _ = try directory(home, "Library/Application Support/Example/Profile/Crashpad/pending")
    _ = try directory(home, "Library/Application Support/Example/Crashpad/new")
    _ = try directory(home, "Library/Application Support/Example/Profile/Extra/Crashpad/new")
    let paths = Targets.all(home: home).map(\.relativePath)
    #expect(paths.contains("Library/Caches/Example.ShipIt"))
    #expect(paths.contains("Library/Application Support/Example/Profile/Crashpad/pending"))
    #expect(paths.contains("Library/Application Support/Example/Crashpad/new"))
    #expect(!paths.contains("Library/Application Support/Example/Profile/Extra/Crashpad/new"))
    let config = try Config.load(home: home)
    #expect(config.metaGB == 30 && !config.vigilancia && config.intervaloHoras == 3)
}
@Test func replacementLinkAfterPreviewIsRefused() throws {
    let home = try fixture(), root = try directory(home, "Library/Caches/pip")
    let original = try file(root, "cache")
    let target = Targets.fixed.first { $0.relativePath == "Library/Caches/pip" }!
    let plan = Scanner(home: home).scan(target), fake = FakeTrasher(home: home)
    try FileManager.default.moveItem(at: original, to: root.appendingPathComponent("renamed"))
    let docs = try directory(home, "Documents")
    try FileManager.default.createSymbolicLink(at: original, withDestinationURL: docs)
    #expect(throws: SafetyError.self) { _ = try Cleaner(home: home, trasher: fake).execute([plan], running: { [] }) }
    #expect(fake.calls.isEmpty)
}
@Test func tamperedManifestCannotRestoreOutsideAllowlist() throws {
    let home = try fixture(), fake = FakeTrasher(home: home)
    let journals = try directory(home, "Library/Application Support/DiscoSeguro/manifests")
    let trash = try directory(home, ".Trash"), item = try file(trash, "item")
    let docs = try directory(home, "Documents")
    let manifest = Manifest(items: [.init(original: docs.appendingPathComponent("victim").path, naLixeira: item.path, bytes: 8192)])
    try JSONEncoder().encode(manifest).write(to: journals.appendingPathComponent("2099.json"))
    #expect(throws: SafetyError.self) { _ = try Undo(home: home, trasher: fake).latest() }
    #expect(PathGuard.exists(item))
}
@Test func configRefusesSymlink() throws {
    let home = try fixture(), folder = try directory(home, "Library/Application Support/DiscoSeguro")
    let docs = try directory(home, "Documents"), outside = try file(docs, "config.json")
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("config.json"), withDestinationURL: outside)
    #expect(throws: SafetyError.self) { try Config().save(home: home) }
}
