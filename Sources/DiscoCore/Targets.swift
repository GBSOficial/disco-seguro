import Foundation
public struct CacheTarget: Identifiable, Hashable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let owners: [String]
    public let logs: Bool
    public var name: String { relativePath }
    init(_ path: String, _ owners: [String] = [], logs: Bool = false) { relativePath = path; self.owners = owners; self.logs = logs }
    public func url(home: URL) -> URL { home.appendingPathComponent(relativePath) }
}
public enum Targets {
    public static let fixed: [CacheTarget] = [
        .init("Library/Caches/Google/Chrome", ["com.google.Chrome"]),
        .init("Library/Caches/Microsoft Edge", ["com.microsoft.edgemac"]),
        .init("Library/Caches/BraveSoftware", ["com.brave.Browser"]),
        .init("Library/Caches/Firefox", ["org.mozilla.firefox"]),
        .init("Library/Caches/Arc", ["company.thebrowser.Browser"]),
        .init("Library/Caches/com.spotify.client", ["com.spotify.client"]),
        .init("Library/Caches/Adobe Camera Raw 2", ["com.adobe.LightroomClassicCC7", "com.adobe.Photoshop"]),
        .init("Library/Caches/claude-cli-nodejs"), .init("Library/Caches/Codex", ["com.openai.codex"]),
        .init("Library/Caches/pip"), .init("Library/Caches/pnpm"), .init("Library/Caches/Yarn"),
        .init("Library/Caches/Homebrew"), .init("Library/Caches/go-build"), .init("Library/Caches/CocoaPods"),
        .init(".npm/_cacache"), .init(".cache/uv"),
        .init("Library/Developer/Xcode/DerivedData", ["com.apple.dt.Xcode"]), .init("Library/Logs", logs: true)
    ]
    public static let informational = ["Downloads", ".codex/sessions", ".claude/projects", ".cache/huggingface/hub", ".ollama", ".lmstudio", "Library/Containers/com.docker.docker", "Library/Application Support/MobileSync/Backup", "Library/Developer/CoreSimulator", "Movies", "Library/Application Support/Claude/vm_bundles"]
    public static func all(home: URL) -> [CacheTarget] {
        let guarder = PathGuard(home: home)
        func directories(_ parent: URL) -> [URL] {
            guard (try? guarder.validate(parent, root: parent, allowRoot: true)) != nil else { return [] }
            return ((try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).filter {
                (try? guarder.validate($0, root: parent)) != nil && ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
            }
        }
        var result = fixed
        for dir in directories(home.appendingPathComponent("Library/Caches")) where dir.lastPathComponent.hasSuffix(".ShipIt") {
            result.append(.init("Library/Caches/" + dir.lastPathComponent))
        }
        let support = home.appendingPathComponent("Library/Application Support")
        let first = directories(support)
        for parent in first + first.flatMap({ directories($0) }) {
            let crash = parent.appendingPathComponent("Crashpad")
            for name in ["pending", "completed", "new"] {
                let dir = crash.appendingPathComponent(name)
                if (try? guarder.validate(dir, root: dir, allowRoot: true)) != nil && FileManager.default.fileExists(atPath: dir.path) {
                    result.append(.init(dir.pathComponents.dropFirst(home.standardizedFileURL.pathComponents.count).joined(separator: "/")))
                }
            }
        }
        return Array(Set(result)).sorted { $0.id < $1.id }
    }
}
