import Foundation
import Testing
@testable import DiscoCore

@Test func cpuTickDeltas() {
    #expect(HealthMath.cpu(previous: [10, 20, 30, 40], current: [20, 30, 60, 50]) == 50)
    #expect(HealthMath.cpu(previous: [1, 2, 3, 4], current: [1, 2, 3, 4]) == 0)
    #expect(HealthMath.cpu(previous: [], current: [1, 2, 3, 4]) == 0)
    #expect(HealthMath.cpu(previous: [100, 100, 100, 100], current: [0, 0, 0, 0]) == 0)
}
@Test func counterRates() {
    #expect(HealthMath.rate(previous: 100, current: 300, seconds: 2) == 100)
    #expect(HealthMath.rate(previous: 300, current: 100, seconds: 2) == 0)
    #expect(HealthMath.rate(previous: 100, current: 300, seconds: 0) == 0)
    var sampler = CounterSampler()
    #expect(sampler.sample(100, 200, now: 1).0 == 0)
    let next = sampler.sample(500, 1000, now: 3)
    #expect(next.0 == 200 && next.1 == 400)
    let reset = sampler.sample(1, 2, now: 5)
    #expect(reset.0 == 0 && reset.1 == 0)
}
@Test func healthAlertPriorities() {
    func level(_ seconds: Double = 0, _ pressure: MemoryPressure = .normal, _ free: Int64? = 40_000_000_000, _ thermal: Bool = false) -> HealthLevel {
        HealthMath.alert(cpuHighSeconds: seconds, pressure: pressure, free: free, goal: 30e9, thermalCritical: thermal).level
    }
    #expect(level() == .normal)
    #expect(level(29) == .normal)
    #expect(level(30) == .orange)
    #expect(level(0, .warning) == .orange)
    #expect(level(0, .normal, 20_000_000_000) == .orange)
    #expect(level(0, .critical) == .red)
    #expect(level(30, .warning, 4_999_999_999) == .red)
    #expect(level(0, .normal, nil, true) == .red)
    #expect(level(0, .unavailable, nil) == .normal)
}
@Test func terminationPolicy() {
    func allowed(_ bundle: String? = "org.example.editor", _ regular: Bool = true, _ sameUser: Bool = true, _ pid: Int32 = 42) -> Bool {
        HealthMath.canTerminate(bundleID: bundle, ownBundleID: "com.gbsoficial.disco-seguro", pid: pid, ownPID: 7, regular: regular, sameUser: sameUser)
    }
    #expect(allowed())
    #expect(!allowed("com.apple.Safari"))
    #expect(!allowed("com.apple.Music"))
    #expect(!allowed("com.gbsoficial.disco-seguro"))
    #expect(!allowed(nil))
    #expect(!allowed("org.example.editor", false))
    #expect(!allowed("org.example.editor", true, false))
    #expect(!allowed("org.example.editor", true, true, 7))
}
@Test func unavailableHardwareFormatting() {
    let summary = HealthFormat.summary(HealthSnapshot())
    #expect(summary.contains("GPU: indisponível"))
    #expect(summary.contains("Bateria: indisponível"))
    #expect(summary.contains("CPU:"))
    #expect(summary.contains("Mais pesados agora"))
}
