import Foundation
import Darwin
import IOKit
import IOKit.ps

private func sysValue<T: BitwiseCopyable>(_ name: String, _ initial: T) -> T? {
    var value = initial, size = MemoryLayout<T>.size
    return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
}
public struct CPUSampler {
    private var previous: [[UInt64]] = []
    public init() {}
    public mutating func sample() -> (Double, [Double]) {
        var count: natural_t = 0, info: processor_info_array_t?, size: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &size) == KERN_SUCCESS, let info else { return (0, []) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(size) * vm_size_t(MemoryLayout<integer_t>.size)) }
        let ticks = (0..<Int(count)).map { core in (0..<4).map { UInt64(UInt32(bitPattern: info[core * 4 + $0])) } }
        let values = ticks.enumerated().map { index, tick in HealthMath.cpu(previous: previous.indices.contains(index) ? previous[index] : tick, current: tick) }
        previous = ticks
        return (values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count), values)
    }
}
public enum MemorySampler {
    public static func pressure() -> MemoryPressure {
        switch sysValue("kern.memorystatus_vm_pressure_level", Int32(0)) { case 1: .normal; case 2: .warning; case 4: .critical; default: .unavailable }
    }
    public static func sample() -> MemoryReading {
        var result = MemoryReading()
        result.total = sysValue("hw.memsize", UInt64(0)) ?? 0
        result.pressure = pressure()
        var stats = vm_statistics64(), count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &stats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) } }
        if status == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return result }
            let page = UInt64(pageSize)
            let occupied = UInt64(stats.active_count) + UInt64(stats.inactive_count)
            let reclaimable = UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)
            let app = occupied > reclaimable ? occupied - reclaimable : 0
            result.used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
            result.cache = reclaimable * page
        }
        result.swap = sysValue("vm.swapusage", xsw_usage())?.xsu_used ?? 0
        return result
    }
}
private func registryStatistics(_ service: String, key: String) -> [[String: Any]] {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(service), &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }
    var values: [[String: Any]] = []
    while true {
        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { break }
        if let property = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] { values.append(property) }
        IOObjectRelease(entry)
    }
    return values
}
public enum GPUSampler {
    public static func sample() -> Double? {
        registryStatistics("IOAccelerator", key: "PerformanceStatistics").compactMap { ($0["Device Utilization %"] as? NSNumber)?.doubleValue }.max().map { min(100, max(0, $0)) }
    }
}
public struct CounterSampler {
    private var previous: (UInt64, UInt64, Double)?
    public init() {}
    public mutating func sample(_ a: UInt64, _ b: UInt64, now: Double) -> (Double, Double) {
        defer { previous = (a, b, now) }
        guard let p = previous else { return (0, 0) }
        return (HealthMath.rate(previous: p.0, current: a, seconds: now - p.2), HealthMath.rate(previous: p.1, current: b, seconds: now - p.2))
    }
}
public struct DiskIOSampler {
    private var delta = CounterSampler()
    public init() {}
    public mutating func sample(now: Double) -> (Double, Double) {
        let stats = registryStatistics("IOBlockStorageDriver", key: "Statistics")
        let read = stats.reduce(UInt64(0)) { $0 + (($1["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0) }
        let written = stats.reduce(UInt64(0)) { $0 + (($1["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0) }
        return delta.sample(read, written, now: now)
    }
}
public struct NetworkSampler {
    private var deltas: [String: CounterSampler] = [:]
    public init() {}
    public mutating func sample(now: Double) -> (Double, Double) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return (0, 0) }
        defer { freeifaddrs(first) }
        var cursor = first, seen: Set<String> = [], input = 0.0, output = 0.0
        while let pointer = cursor {
            let item = pointer.pointee
            cursor = item.ifa_next
            guard let address = item.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  item.ifa_flags & UInt32(IFF_UP) != 0, item.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let data = item.ifa_data else { continue }
            let name = String(cString: item.ifa_name)
            guard seen.insert(name).inserted else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            var delta = deltas[name] ?? CounterSampler()
            let rates = delta.sample(UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes), now: now)
            deltas[name] = delta; input += rates.0; output += rates.1
        }
        deltas = deltas.filter { seen.contains($0.key) }
        return (input, output)
    }
}
public enum BatterySampler {
    public static func sample() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? NSNumber, let max = d[kIOPSMaxCapacityKey] as? NSNumber, max.doubleValue > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = (d[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
            return .init(percent: current.doubleValue / max.doubleValue * 100, charging: charging, minutes: minutes.flatMap { $0 > 0 ? $0 : nil })
        }
        return nil
    }
}
public enum ThermalSampler {
    public static func sample() -> String {
        switch ProcessInfo.processInfo.thermalState { case .nominal: "Normal"; case .fair: "Morno"; case .serious: "Quente"; case .critical: "Crítico"; @unknown default: "Indisponível" }
    }
}
public struct ProcessSampler {
    private var previous: [Int32: (UInt64, UInt64)] = [:]
    private var time: Double?
    public init() {}
    static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()
    public static func identity(_ pid: Int32) -> (uid: uid_t, started: UInt64)? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info) else { return nil }
        return (info.pbi_uid, info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }
    public mutating func sample(now: Double) -> [ProcessReading] {
        let capacity = Int(proc_listallpids(nil, 0)) + 128
        guard capacity > 128 else { return [] }
        var pids = [Int32](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var readings: [ProcessReading] = [], next: [Int32: (UInt64, UInt64)] = [:]
        for pid in pids.prefix(min(max(0, Int(count)), capacity)) where pid > 0 {
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info), let identity = Self.identity(pid) else { continue }
            // proc_taskinfo reports mach ticks, not nanoseconds (Apple Silicon: 125/3 ns per tick).
            let cpuTime = (info.pti_total_user + info.pti_total_system) &* Self.timebase.numer / Self.timebase.denom
            var name = [CChar](repeating: 0, count: 1024)
            let length = proc_name(pid, &name, UInt32(name.count))
            let label = length > 0 ? String(decoding: name.prefix(Int(length)).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : "Processo \(pid)"
            let old = previous[pid]
            let cpu = old?.1 == identity.started ? HealthMath.rate(previous: old!.0, current: cpuTime, seconds: now - (time ?? now)) / 1e9 * 100 : 0
            readings.append(.init(pid: pid, name: label, cpu: cpu, memory: info.pti_resident_size, started: identity.started))
            next[pid] = (cpuTime, identity.started)
        }
        previous = next; time = now
        return readings
    }
}
