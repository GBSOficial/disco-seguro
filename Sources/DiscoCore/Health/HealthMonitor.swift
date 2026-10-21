import Foundation

/// One owner per collector; UI uses the actor below, CLI owns its local collector.
public struct HealthCollector {
    private var cpu = CPUSampler()
    private var disk = DiskIOSampler()
    private var network = NetworkSampler()
    private var processes = ProcessSampler()
    public init() {}
    public mutating func sample(full: Bool, home: URL) -> HealthSnapshot {
        var s = HealthSnapshot()
        let now = ProcessInfo.processInfo.systemUptime
        let usage = cpu.sample()
        s.cpu = usage.0
        s.free = (try? DiskInfo(home: home))?.free
        s.memory.pressure = MemorySampler.pressure()
        guard full else { return s }
        s.cores = usage.1
        s.memory = MemorySampler.sample()
        s.gpu = GPUSampler.sample()
        (s.diskRead, s.diskWrite) = disk.sample(now: now)
        (s.networkIn, s.networkOut) = network.sample(now: now)
        s.battery = BatterySampler.sample()
        s.thermal = ThermalSampler.sample()
        s.processes = processes.sample(now: now)
        return s
    }
    public mutating func resetForeground() {
        disk = DiskIOSampler(); network = NetworkSampler(); processes = ProcessSampler()
    }
}
public actor HealthMonitor {
    private var collector = HealthCollector()
    private var history: [HealthSnapshot] = []
    private var wasFull = false
    public init() {}
    public func sample(full: Bool, home: URL) -> (HealthSnapshot, [HealthSnapshot]) {
        if full != wasFull { collector.resetForeground() }
        wasFull = full
        let snapshot = collector.sample(full: full, home: home)
        if full {
            // History contains chart data only, never retained process lists.
            var point = snapshot; point.processes = []
            history.append(point)
            history = Array(history.filter { snapshot.date.timeIntervalSince($0.date) <= 120 }.suffix(60))
        }
        return (snapshot, history)
    }
}
