import Foundation

public enum MemoryPressure: String, Sendable { case normal = "Normal", warning = "Aviso", critical = "Crítico", unavailable = "Indisponível" }
public enum HealthLevel: Sendable { case normal, orange, red }
public struct HealthAlert: Sendable {
    public let level: HealthLevel
    public let reasons: [String]
}
public enum HealthMath {
    public static func rate(previous: UInt64, current: UInt64, seconds: Double) -> Double {
        guard seconds > 0, current >= previous else { return 0 }
        return Double(current - previous) / seconds
    }
    public static func cpu(previous: [UInt64], current: [UInt64]) -> Double {
        guard previous.count == 4, current.count == 4 else { return 0 }
        let delta = zip(previous, current).map { $1 >= $0 ? $1 - $0 : 0 }
        let total = delta.reduce(0, +)
        return total == 0 ? 0 : Double(total - delta[2]) / Double(total) * 100
    }
    public static func alert(cpuHighSeconds: Double, pressure: MemoryPressure, free: Int64?, goal: Double, thermalCritical: Bool) -> HealthAlert {
        var red: [String] = [], orange: [String] = []
        if pressure == .critical { red.append("Pressão de memória crítica") }
        if thermalCritical { red.append("Temperatura crítica") }
        if let free, free < 5_000_000_000 { red.append("Menos de 5 GB livres") }
        if cpuHighSeconds >= 30 { orange.append("CPU acima de 85% por 30 s") }
        if pressure == .warning { orange.append("Pressão de memória elevada") }
        if let free, Double(free) < goal { orange.append("Espaço abaixo da meta") }
        return .init(level: !red.isEmpty ? .red : !orange.isEmpty ? .orange : .normal, reasons: red + orange)
    }
    public static func canTerminate(bundleID: String?, ownBundleID: String, pid: Int32, ownPID: Int32, regular: Bool, sameUser: Bool) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return regular && sameUser && pid != ownPID && bundleID != ownBundleID && !bundleID.hasPrefix("com.apple.")
    }
}
public struct MemoryReading: Sendable {
    public var total: UInt64 = 0, used: UInt64 = 0, cache: UInt64 = 0, swap: UInt64 = 0
    public var pressure: MemoryPressure = .unavailable
    public init() {}
}
public struct BatteryReading: Sendable {
    public let percent: Double
    public let charging: Bool
    public let minutes: Int?
}
public struct ProcessReading: Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let cpu: Double
    public let memory: UInt64
    public let started: UInt64
}
public struct HealthSnapshot: Sendable {
    public var date = Date()
    public var cpu: Double = 0
    public var cores: [Double] = []
    public var memory = MemoryReading()
    public var gpu: Double?
    public var free: Int64?
    public var diskRead: Double = 0, diskWrite: Double = 0, networkIn: Double = 0, networkOut: Double = 0
    public var battery: BatteryReading?
    public var thermal = "Normal"
    public var processes: [ProcessReading] = []
    public init() {}
}
public enum HealthFormat {
    public static func percent(_ value: Double) -> String { String(format: "%.1f%%", locale: Locale(identifier: "pt_BR"), value) }
    public static func bytes(_ value: UInt64) -> String { DiskInfo.format(Int64(clamping: value)) }
    public static func rate(_ value: Double) -> String { String(format: "%.2f MB/s", locale: Locale(identifier: "pt_BR"), value / 1e6) }
    public static func battery(_ value: BatteryReading?) -> String {
        guard let value else { return "indisponível" }
        return "\(percent(value.percent)) · \(value.charging ? "Carregando" : "Não está carregando") · \(value.minutes.map { "\($0) min" } ?? "tempo indisponível")"
    }
    public static func summary(_ s: HealthSnapshot) -> String {
        """
        CPU: \(percent(s.cpu))
        Memória: \(bytes(s.memory.used)) / \(bytes(s.memory.total)) · \(s.memory.pressure.rawValue); cache: \(bytes(s.memory.cache)); swap: \(bytes(s.memory.swap))
        GPU: \(s.gpu.map(percent) ?? "indisponível")
        Disco: \(s.free.map(DiskInfo.format) ?? "indisponível") livres · leitura \(rate(s.diskRead)) · gravação \(rate(s.diskWrite))
        Rede: ↓ \(rate(s.networkIn)) · ↑ \(rate(s.networkOut))
        Bateria: \(battery(s.battery))
        Temperatura: \(s.thermal)
        Mais pesados agora (% CPU por núcleo):
        \(s.processes.sorted { $0.cpu > $1.cpu }.prefix(5).map { "\($0.name) · \(percent($0.cpu)) · \(bytes($0.memory)) · PID \($0.pid)" }.joined(separator: "\n"))
        """
    }
}
