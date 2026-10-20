import Foundation
public struct ScanItem: Sendable {
    public let url: URL
    public let bytes: Int64
}
public struct ScanResult: Identifiable, Sendable {
    public var id: String { target.id }
    public let target: CacheTarget
    public let items: [ScanItem]
    public let blocked: String?
    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}
public struct Scanner: Sendable {
    public let home: URL
    public init(home: URL) { self.home = home }
    public func size(_ url: URL) -> Int64 {
        guard !PathGuard.isLink(url) else { return 0 }
        guard let value = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else { return 0 }
        if value.isRegularFile == true { return Int64(value.totalFileAllocatedSize ?? value.fileAllocatedSize ?? 0) }
        guard value.isDirectory == true else { return 0 }
        return ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).reduce(0) { $0 + size($1) }
    }
    public func informativeSize(_ url: URL) -> Int64 {
        guard (try? PathGuard(home: home).validate(url, root: url, allowRoot: true)) != nil else { return 0 }
        return size(url)
    }
    public func scan(_ target: CacheTarget, running: Set<String> = [], now: Date = Date()) -> ScanResult {
        if let owner = target.owners.first(where: running.contains) { return .init(target: target, items: [], blocked: "feche o \(owner)") }
        let root = target.url(home: home), guarder = PathGuard(home: home)
        do { try guarder.validate(root, root: root, allowRoot: true) } catch { return .init(target: target, items: [], blocked: error.localizedDescription) }
        guard FileManager.default.fileExists(atPath: root.path) else { return .init(target: target, items: [], blocked: nil) }
        var items: [ScanItem] = []
        func visit(_ directory: URL) throws {
            for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]) {
                guard (try? guarder.validate(child, root: root)) != nil else { continue }
                let value = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey])
                if target.logs {
                    if value.isDirectory == true { try visit(child) }
                    else if value.isRegularFile == true, let date = value.contentModificationDate, now.timeIntervalSince(date) > 7 * 86400 { items.append(.init(url: child, bytes: size(child))) }
                } else if value.isDirectory == true || value.isRegularFile == true { items.append(.init(url: child, bytes: size(child))) }
            }
        }
        do { try visit(root) } catch { return .init(target: target, items: [], blocked: "Não foi possível ler: \(error.localizedDescription)") }
        return .init(target: target, items: items.sorted { $0.url.path < $1.url.path }, blocked: nil)
    }
}
