import Foundation
public struct Undo {
    public let home: URL
    public let trasher: any Trasher
    public init(home: URL, trasher: any Trasher = SystemTrasher()) { self.home = home; self.trasher = trasher }
    public func latest(running: () -> Set<String> = { [] }) throws -> Int {
        let directory = Cleaner(home: home).manifestsDirectory, guarder = PathGuard(home: home)
        try guarder.validate(directory, root: directory, allowRoot: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        let targets = Targets.all(home: home)
        for file in files {
            try guarder.validate(file, root: directory)
            var manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
            guard !manifest.items.isEmpty else { continue }
            var restored = 0
            for entry in manifest.items.reversed() {
                let original = URL(fileURLWithPath: entry.original), trash = URL(fileURLWithPath: entry.naLixeira)
                guard let target = targets.first(where: { target in
                    let root = target.url(home: home)
                    return target.logs ? PathGuard.inside(original, root) : original.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
                }) else { throw SafetyError.denied("Manifesto contém destino não permitido") }
                try guarder.validate(original, root: target.url(home: home))
                try guarder.validate(trash, root: home.appendingPathComponent(".Trash"))
                guard !PathGuard.exists(original), PathGuard.exists(trash), target.owners.allSatisfy({ !running().contains($0) }) else { continue }
                guard FileManager.default.fileExists(atPath: original.deletingLastPathComponent().path) else { continue }
                try trasher.restore(trash, to: original)
                manifest.items.removeAll { $0.original == entry.original && $0.naLixeira == entry.naLixeira }
                try guarder.validate(file, root: directory)
                try JSONEncoder().encode(manifest).write(to: file, options: .atomic)
                restored += 1
            }
            return restored
        }
        return 0
    }
}
