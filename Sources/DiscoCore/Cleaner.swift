import Foundation
public protocol Trasher {
    func trash(_ url: URL) throws -> URL
    func restore(_ trashed: URL, to original: URL) throws
}
public struct SystemTrasher: Trasher {
    public init() {}
    public func trash(_ url: URL) throws -> URL {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        guard let destination else { throw SafetyError.denied("A Lixeira não informou o destino") }
        return destination as URL
    }
    public func restore(_ trashed: URL, to original: URL) throws { try FileManager.default.moveItem(at: trashed, to: original) }
}
public struct ManifestItem: Codable, Sendable {
    public let original: String
    public let naLixeira: String
    public let bytes: Int64
}
public struct Manifest: Codable, Sendable {
    public var items: [ManifestItem]
}
public struct Cleaner {
    public let home: URL
    public let trasher: any Trasher
    public init(home: URL, trasher: any Trasher = SystemTrasher()) { self.home = home; self.trasher = trasher }
    public var manifestsDirectory: URL { home.appendingPathComponent("Library/Application Support/DiscoSeguro/manifests") }
    public func execute(_ plan: [ScanResult], running: () -> Set<String>) throws -> URL {
        let guarder = PathGuard(home: home), allowed = Targets.all(home: home)
        try guarder.prepareDirectory(manifestsDirectory)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = manifestsDirectory.appendingPathComponent("\(stamp)-\(UUID().uuidString).json")
        var manifest = Manifest(items: [])
        func save() throws {
            try guarder.validate(file, root: manifestsDirectory)
            try JSONEncoder().encode(manifest).write(to: file, options: .atomic)
        }
        // Ensure the journal can be written before touching any cache.
        try save()
        for result in plan where result.blocked == nil {
            guard allowed.contains(result.target) else { throw SafetyError.denied("Alvo fora da lista permitida") }
            let root = result.target.url(home: home)
            for item in result.items {
                guard result.target.owners.allSatisfy({ !running().contains($0) }) else { throw SafetyError.denied("O aplicativo dono foi aberto; limpeza interrompida") }
                try guarder.validate(item.url, root: root)
                if result.target.logs {
                    let values = try item.url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                    guard values.isRegularFile == true, let date = values.contentModificationDate, Date().timeIntervalSince(date) > 7 * 86400 else { throw SafetyError.denied("Log recente ou inválido") }
                } else {
                    guard item.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw SafetyError.denied("Item não é filho direto") }
                }
                let bytes = Scanner(home: home).size(item.url)
                guard bytes == item.bytes else { throw SafetyError.denied("O tamanho mudou. Faça outra prévia antes de limpar.") }
                let destination = try trasher.trash(item.url)
                manifest.items.append(.init(original: item.url.path, naLixeira: destination.path, bytes: bytes))
                do { try save() } catch {
                    // Roll back this item if journaling fails; earlier entries remain journaled.
                    if !PathGuard.exists(item.url) { try trasher.restore(destination, to: item.url) }
                    throw error
                }
            }
        }
        return file
    }
}
