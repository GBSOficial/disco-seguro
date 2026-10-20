import Foundation
import Darwin
public enum SafetyError: Error, LocalizedError {
    case denied(String)
    public var errorDescription: String? { switch self { case .denied(let reason): return reason } }
}
public struct PathGuard: Sendable {
    public let home: URL
    public init(home: URL) { self.home = home.standardizedFileURL }
    public static func isLink(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }
    public static func exists(_ url: URL) -> Bool {
        var info = stat(); return lstat(url.path, &info) == 0
    }
    public static func inside(_ url: URL, _ root: URL, allowRoot: Bool = false) -> Bool {
        let p = url.standardizedFileURL.pathComponents, r = root.standardizedFileURL.pathComponents
        return p.starts(with: r) && (allowRoot ? p.count >= r.count : p.count > r.count)
    }
    public func validate(_ item: URL, root: URL, allowRoot: Bool = false) throws {
        let root = root.standardizedFileURL, item = item.standardizedFileURL
        guard Self.inside(root, home), Self.inside(item, root, allowRoot: allowRoot) else { throw SafetyError.denied("Caminho fora da raiz permitida: \(item.path)") }
        for path in [root, item] {
            let real = path.resolvingSymlinksInPath()
            guard Self.inside(real, home.resolvingSymlinksInPath()), !["/System", "/Library", "/private", "/usr"].contains(where: { Self.inside(real, URL(fileURLWithPath: $0), allowRoot: true) }) else { throw SafetyError.denied("Caminho protegido: \(path.path)") }
            var cursor = path
            while cursor.path != "/" {
                guard !Self.isLink(cursor) else { throw SafetyError.denied("Link simbólico recusado: \(cursor.path)") }
                cursor.deleteLastPathComponent()
            }
        }
        guard Self.inside(item.resolvingSymlinksInPath(), root.resolvingSymlinksInPath(), allowRoot: allowRoot) else { throw SafetyError.denied("Destino fora da raiz") }
    }
    public func prepareDirectory(_ url: URL) throws {
        try validate(url, root: home.appendingPathComponent("Library"))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try validate(url, root: home.appendingPathComponent("Library"))
    }
}
