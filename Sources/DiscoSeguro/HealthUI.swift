import AppKit
import SwiftUI
import Charts
import DiscoCore
import Darwin

@MainActor final class HealthModel: ObservableObject {
    @Published var snapshot = HealthSnapshot()
    @Published var history: [HealthSnapshot] = []
    @Published var alert = HealthMath.alert(cpuHighSeconds: 0, pressure: .normal, free: nil, goal: 0, thermalCritical: false)
    private let monitor = HealthMonitor()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var highSince: Date?
    var panelVisible = false { didSet { if oldValue != panelVisible { schedule() } } }
    var windowVisible = false { didSet { if oldValue != windowVisible { schedule() } } }
    var onAlert: ((HealthAlert) -> Void)?
    func start() { schedule() }
    private func schedule() {
        task?.cancel(); generation += 1
        let token = generation
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let full = self.panelVisible || self.windowVisible
                let (s, history) = await self.monitor.sample(full: full, home: FileManager.default.homeDirectoryForCurrentUser)
                guard !Task.isCancelled, token == self.generation else { return }
                self.snapshot = s; self.history = history
                if s.cpu > 85 { if self.highSince == nil { self.highSince = s.date } } else { self.highSince = nil }
                let goal = ((try? Config.load(home: FileManager.default.homeDirectoryForCurrentUser))?.metaGB ?? 30) * 1e9
                // thermalState is a cached system property, not a hardware temperature probe.
                self.alert = HealthMath.alert(cpuHighSeconds: self.highSince.map { s.date.timeIntervalSince($0) } ?? 0, pressure: s.memory.pressure, free: s.free, goal: goal, thermalCritical: ProcessInfo.processInfo.thermalState == .critical)
                self.onAlert?(self.alert)
                do { try await Task.sleep(for: .seconds(full ? 2 : 10)) } catch { return }
            }
        }
    }
}

enum HealthMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memória", gpu = "GPU", disk = "Disco", network = "Rede", battery = "Bateria", thermal = "Temperatura", processes = "Processos"
    var id: String { rawValue }
    func value(_ s: HealthSnapshot) -> Double? {
        switch self {
        case .cpu: s.cpu
        case .memory: Double(s.memory.used) / 1e9
        case .gpu: s.gpu
        case .disk: s.diskRead / 1e6
        case .network: s.networkIn / 1e6
        case .battery: s.battery?.percent
        default: nil
        }
    }
    func second(_ s: HealthSnapshot) -> Double? {
        switch self { case .disk: s.diskWrite / 1e6; case .network: s.networkOut / 1e6; default: nil }
    }
    var unit: String { switch self { case .memory: "GB"; case .disk, .network: "MB/s"; default: "%" } }
    var firstLabel: String { switch self { case .disk: "Leitura"; case .network: "Recebidos"; default: rawValue } }
    var secondLabel: String { self == .disk ? "Gravação" : "Enviados" }
    func title(_ s: HealthSnapshot) -> String {
        switch self {
        case .cpu: HealthFormat.percent(s.cpu)
        case .memory: HealthFormat.bytes(s.memory.used)
        case .gpu: s.gpu.map(HealthFormat.percent) ?? "indisponível"
        case .disk: (s.free.map(DiskInfo.format) ?? "indisponível") + " livres"
        case .network: "↓ " + HealthFormat.rate(s.networkIn)
        case .battery: s.battery.map { HealthFormat.percent($0.percent) } ?? "indisponível"
        case .thermal: s.thermal
        case .processes: "Mais pesados agora"
        }
    }
    func details(_ s: HealthSnapshot) -> String {
        switch self {
        case .cpu: "\(s.cores.count) núcleos · uso total normalizado"
        case .memory: "Pressão: \(s.memory.pressure.rawValue) · total: \(HealthFormat.bytes(s.memory.total))\nCache: \(HealthFormat.bytes(s.memory.cache)) · swap: \(HealthFormat.bytes(s.memory.swap))"
        case .gpu: "Utilização informada pelo driver"
        case .disk: "Leitura: \(HealthFormat.rate(s.diskRead)) · gravação: \(HealthFormat.rate(s.diskWrite))\nEspaço do volume pessoal; E/S de todos os discos"
        case .network: "↑ \(HealthFormat.rate(s.networkOut)) · interfaces ativas (podem incluir VPN)"
        case .battery: HealthFormat.battery(s.battery)
        case .thermal: "Estado térmico do macOS; não mede graus Celsius"
        case .processes: "% CPU por núcleo (pode ultrapassar 100%)"
        }
    }
}
struct HealthGraph: View {
    let history: [HealthSnapshot]
    let metric: HealthMetric
    var compact = false
    var body: some View {
        Chart {
            ForEach(history, id: \.date) { point in
                if let value = metric.value(point) {
                    LineMark(x: .value("Hora", point.date), y: .value(metric.unit, value))
                        .foregroundStyle(by: .value("Série", metric.firstLabel))
                }
                if let value = metric.second(point) {
                    LineMark(x: .value("Hora", point.date), y: .value(metric.unit, value))
                        .foregroundStyle(by: .value("Série", metric.secondLabel))
                }
            }
        }
        .chartXScale(domain: Date().addingTimeInterval(-120)...Date())
        .chartXAxis(compact ? .hidden : .automatic)
        .chartYAxis(compact ? .hidden : .automatic)
        .chartLegend(compact ? .hidden : .automatic)
        .accessibilityLabel("Histórico de \(metric.rawValue), últimos dois minutos, em \(metric.unit)")
    }
}
struct HealthPanel: View {
    @ObservedObject var model: HealthModel
    let openMonitor: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(HealthMetric.allCases.filter { $0 != .processes }) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.rawValue).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(metric.title(model.snapshot)).font(.title3.bold())
                            Spacer()
                            if metric.value(model.snapshot) != nil { HealthGraph(history: model.history, metric: metric, compact: true).frame(width: 100, height: 32) }
                        }
                        Text(metric.details(model.snapshot)).font(.caption).foregroundStyle(.secondary)
                    }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                Text("Mais pesados agora").font(.headline)
                ForEach(model.snapshot.processes.sorted { $0.cpu > $1.cpu }.prefix(5)) { process in
                    HStack { Text(process.name).lineLimit(1); Spacer(); Text(HealthFormat.percent(process.cpu)).monospacedDigit() }.font(.caption)
                }
                Button("Abrir Monitor completo", action: openMonitor).buttonStyle(.borderedProminent)
            }.padding(14)
        }
    }
}
struct PopoverView: View {
    @ObservedObject var model: Model
    @ObservedObject var health: HealthModel
    let openMonitor: () -> Void
    @State private var tab = "Limpeza"
    var body: some View {
        VStack(spacing: 0) {
            Picker("Painel", selection: $tab) { Text("Limpeza").tag("Limpeza"); Text("Saúde").tag("Saúde") }.pickerStyle(.segmented).padding([.horizontal, .top], 14)
            if tab == "Limpeza" { ContentView(model: model) } else { HealthPanel(model: health, openMonitor: openMonitor) }
        }
    }
}

@MainActor enum ProcessActions {
    static func allowed(_ row: ProcessReading, app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, let identity = ProcessSampler.identity(row.pid), identity.started == row.started else { return false }
        return HealthMath.canTerminate(bundleID: app.bundleIdentifier, ownBundleID: Bundle.main.bundleIdentifier ?? "com.biel.disco-seguro", pid: row.pid, ownPID: ProcessInfo.processInfo.processIdentifier, regular: app.activationPolicy == .regular, sameUser: identity.uid == getuid())
    }
    static func canTerminate(_ row: ProcessReading) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: row.pid) else { return false }
        return allowed(row, app: app)
    }
    static func confirm(_ title: String, message: String, button: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: button); alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }
    static func terminate(_ row: ProcessReading) {
        guard let app = NSRunningApplication(processIdentifier: row.pid), allowed(row, app: app),
              confirm("Encerrar \(row.name)?", message: "O aplicativo poderá pedir para salvar documentos.", button: "Encerrar"), allowed(row, app: app) else { return }
        _ = app.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard allowed(row, app: app), confirm("\(row.name) continua aberto", message: "Forçar o encerramento pode perder alterações não salvas.", button: "Forçar encerramento"), allowed(row, app: app) else { return }
            _ = app.forceTerminate()
        }
    }
}
struct ProcessTable: View {
    let processes: [ProcessReading]
    @State private var search = ""
    @State private var selection: Int32?
    @State private var sortOrder = [KeyPathComparator(\ProcessReading.cpu, order: .reverse)]
    private var rows: [ProcessReading] {
        Array(processes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.pid).contains(search) }.sorted(using: sortOrder).prefix(50))
    }
    var body: some View {
        VStack(alignment: .leading) {
            TextField("Buscar nome ou PID", text: $search).textFieldStyle(.roundedBorder)
            Text("Até 50 processos · % CPU por núcleo · clique nos títulos para ordenar").font(.caption).foregroundStyle(.secondary)
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nome", value: \.name)
                TableColumn("% CPU", value: \.cpu) { Text(HealthFormat.percent($0.cpu)) }.width(90)
                TableColumn("Memória", value: \.memory) { Text(HealthFormat.bytes($0.memory)) }.width(110)
                TableColumn("PID", value: \.pid) { Text(String($0.pid)) }.width(80)
            }
            if let row = rows.first(where: { $0.pid == selection }) {
                Button("Encerrar \(row.name)") { ProcessActions.terminate(row) }.disabled(!ProcessActions.canTerminate(row))
            } else { Button("Encerrar") {}.disabled(true) }
            Text("Somente apps comuns do seu usuário. Apps Apple, processos de sistema e o Disco Seguro são protegidos.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct MonitorView: View {
    @ObservedObject var model: HealthModel
    @State private var metric: HealthMetric? = .cpu
    var body: some View {
        NavigationSplitView {
            List(HealthMetric.allCases, selection: $metric) { metric in Text(metric.rawValue).tag(metric) }.navigationTitle("Monitor do Mac")
                .navigationSplitViewColumnWidth(min: 130, ideal: 160, max: 200)
        } detail: {
            if let metric {
                if metric == .processes { ProcessTable(processes: model.snapshot.processes).padding() }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(metric.rawValue).font(.largeTitle)
                            Text(metric.title(model.snapshot)).font(.title.bold())
                            if metric.value(model.snapshot) != nil {
                                Text("Últimos 2 minutos · \(metric.unit)").font(.caption)
                                HealthGraph(history: model.history, metric: metric).frame(height: 250)
                            }
                            Text(metric.details(model.snapshot))
                            if metric == .cpu {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))]) {
                                    ForEach(Array(model.snapshot.cores.enumerated()), id: \.offset) { index, value in
                                        VStack { Text("Núcleo \(index + 1)"); ProgressView(value: value, total: 100); Text(HealthFormat.percent(value)) }.font(.caption).padding(6)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                }
            }
        }.frame(minWidth: 620, minHeight: 400)
    }
}
@MainActor final class HealthWindowController: NSObject, NSWindowDelegate {
    let model: HealthModel
    private var window: NSWindow?
    init(model: HealthModel) { self.model = model }
    func show() {
        if window == nil {
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 620)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(900, visible.width), height: min(620, visible.height - 30)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Monitor do Mac"; window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: MonitorView(model: model))
            window.delegate = self; window.center(); self.window = window
        }
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true); updateVisibility()
    }
    func updateVisibility() { model.windowVisible = window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { model.windowVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }
    func windowWillClose(_ notification: Notification) { model.windowVisible = false }
}
