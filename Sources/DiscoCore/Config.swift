import Foundation
public struct Config: Codable, Sendable {
    public var metaGB: Double = 30
    public var vigilancia = false
    public var intervaloHoras = 3
    public init() {}
    public static func load(home: URL) throws -> Config {
        let file = location(home)
        try PathGuard(home: home).validate(file, root: file.deletingLastPathComponent())
        guard PathGuard.exists(file) else { return Config() }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: file))
        try config.validate(); return config
    }
    public func validate() throws {
        guard metaGB.isFinite, metaGB > 0, metaGB < 1_000_000, intervaloHoras > 0, intervaloHoras <= 8760 else { throw SafetyError.denied("Meta ou intervalo inválido") }
    }
    public func save(home: URL) throws {
        try validate()
        let file = Self.location(home), guarder = PathGuard(home: home)
        try guarder.prepareDirectory(file.deletingLastPathComponent())
        try guarder.validate(file, root: file.deletingLastPathComponent())
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
    static func location(_ home: URL) -> URL { home.appendingPathComponent("Library/Application Support/DiscoSeguro/config.json") }
}
