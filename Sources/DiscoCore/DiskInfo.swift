import Foundation
public struct DiskInfo: Sendable {
    public let free: Int64
    public let total: Int64
    public init(home: URL) throws {
        let values = try home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity else { throw SafetyError.denied("Não foi possível medir o volume") }
        self.free = free; self.total = Int64(total)
    }
    public static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
