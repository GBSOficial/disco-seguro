import AppKit
import SwiftUI
import UserNotifications
import DiscoCore

let home = FileManager.default.homeDirectoryForCurrentUser
@MainActor func running() -> Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
@MainActor func scanAll() -> [ScanResult] { let apps = running(); return Targets.all(home: home).map { Scanner(home: home).scan($0, running: apps) } }
func preview(_ results: [ScanResult]) {
    for result in results {
        print("\(result.target.name): \(DiskInfo.format(result.bytes)), \(result.items.count) itens\(result.blocked.map { " — " + $0 } ?? "")")
        for item in result.items { print("  \(item.url.path) — \(DiskInfo.format(item.bytes))") }
    }
    print("Total: \(DiskInfo.format(results.reduce(0) { $0 + $1.bytes }))")
}
@MainActor func notifyIfNeeded() throws {
    let config = try Config.load(home: home)
    guard config.vigilancia, try DiskInfo(home: home).free < Int64(config.metaGB * 1_000_000_000) else { return }
    guard Bundle.main.bundleIdentifier == "com.biel.disco-seguro" else { throw SafetyError.denied("Notificações exigem o binário instalado no bundle do app.") }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Disco Seguro"
        content.body = "O espaço livre está abaixo da meta. Abra o Disco Seguro para analisar."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "disco-seguro-meta", content: content, trigger: nil))
    }
    RunLoop.current.run(until: Date().addingTimeInterval(3))
}
@MainActor func cli(_ args: [String]) throws {
    switch args.first {
    case "status":
        let disk = try DiskInfo(home: home), config = try Config.load(home: home)
        print("Livre: \(DiskInfo.format(disk.free)) / \(DiskInfo.format(disk.total)); meta: \(config.metaGB) GB; vigilância: \(config.vigilancia ? "ligada" : "desligada")")
    case "analisar":
        preview(scanAll())
        print("Somente informativo — nunca limpo:")
        for path in Targets.informational { print("\(path): \(DiskInfo.format(Scanner(home: home).informativeSize(home.appendingPathComponent(path))))") }
    case "limpar":
        guard args.dropFirst().allSatisfy({ ["--executar", "--sim"].contains($0) }) else { throw SafetyError.denied("Opção desconhecida") }
        let plan = scanAll(); preview(plan)
        guard args.contains("--executar") else { print("Simulação: nenhum arquivo foi movido."); return }
        if !args.contains("--sim") { print("Enviar esses itens para a Lixeira? Digite s:"); guard readLine() == "s" else { print("Cancelado."); return } }
        print("Manifesto: \(try Cleaner(home: home).execute(plan, running: running).path)")
    case "desfazer": print("Restaurados: \(try Undo(home: home).latest(running: running))")
    case "vigiar": try notifyIfNeeded()
    case "vigilancia":
        guard args.count == 2, ["ligar", "desligar"].contains(args[1]) else { throw SafetyError.denied("Use vigilancia ligar|desligar") }
        try Watcher(home: home).setEnabled(args[1] == "ligar", binary: Bundle.main.executableURL!.resolvingSymlinksInPath())
        print("Vigilância \(args[1] == "ligar" ? "ligada" : "desligada"). Autorize notificações nos ajustes do app.")
    case "meta":
        guard args.count == 2, let value = Double(args[1]), value.isFinite, value > 0, value < 1_000_000 else { throw SafetyError.denied("Informe uma meta válida em GB") }
        var config = try Config.load(home: home); config.metaGB = value; try config.save(home: home)
        print("Meta salva: \(value) GB")
    case "ajuda": print("Disco Seguro: status | analisar | limpar [--executar] [--sim] | desfazer | vigiar | vigilancia ligar|desligar | meta <GB> | ajuda\nLimpar sem --executar apenas simula. --sim dispensa a pergunta, mas não a prévia.")
    default: throw SafetyError.denied("Comando desconhecido. Use ajuda.")
    }
}
@MainActor final class Model: ObservableObject {
    @Published var results: [ScanResult] = []
    @Published var selected: Set<String> = []
    @Published var info: [(String, Int64)] = []
    @Published var free: Int64 = 0
    @Published var total: Int64 = 0
    @Published var meta = "30"
    @Published var watching = false
    @Published var message = ""
    func refresh() {
        do {
            let config = try Config.load(home: home), disk = try DiskInfo(home: home)
            meta = String(config.metaGB); watching = config.vigilancia; free = disk.free; total = disk.total
            results = scanAll(); selected = Set(results.filter { $0.blocked == nil }.map(\.id))
            info = Targets.informational.map { ($0, Scanner(home: home).informativeSize(home.appendingPathComponent($0))) }
        } catch { message = error.localizedDescription }
    }
    func clean() {
        // Fresh plan is the exact snapshot confirmed by the user.
        let plan = scanAll().filter { selected.contains($0.id) && $0.blocked == nil }
        let alert = NSAlert(); alert.messageText = "Enviar para a Lixeira?"
        alert.informativeText = plan.map { "\($0.target.name): \(DiskInfo.format($0.bytes)), \($0.items.count) itens" }.joined(separator: "\n") + "\nTotal: " + DiskInfo.format(plan.reduce(0) { $0 + $1.bytes })
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 180)); text.isEditable = false
        text.string = plan.flatMap(\.items).map { "\($0.url.path) — \(DiskInfo.format($0.bytes))" }.joined(separator: "\n")
        let scroll = NSScrollView(frame: text.frame); scroll.documentView = text; scroll.hasVerticalScroller = true; alert.accessoryView = scroll
        alert.addButton(withTitle: "Enviar para a Lixeira"); alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { _ = try Cleaner(home: home).execute(plan, running: running); refresh(); message = "Limpeza concluída. Manifesto salvo." } catch { message = error.localizedDescription }
    }
    func undo() { do { let count = try Undo(home: home).latest(running: running); refresh(); message = "\(count) itens restaurados." } catch { message = error.localizedDescription } }
    func save() {
        do {
            guard let number = Double(meta), number > 0, number < 1_000_000 else { throw SafetyError.denied("Meta inválida") }
            var config = try Config.load(home: home); config.metaGB = number; try config.save(home: home)
            if config.vigilancia != watching { try Watcher(home: home).setEnabled(watching, binary: Bundle.main.executableURL!.resolvingSymlinksInPath()) }
            if watching { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
            message = "Ajustes salvos."
        } catch { message = error.localizedDescription }
    }
}
struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Disco Seguro").font(.title2.bold())
                Text("Livre: \(DiskInfo.format(model.free)) de \(DiskInfo.format(model.total))")
                ProgressView(value: min(Double(model.free) / max((Double(model.meta) ?? 30) * 1e9, 1), 1))
                Text("Espaço livre em relação à meta") .font(.caption)
                Button("Atualizar análise") { model.refresh() }
                ForEach(model.results) { row in
                    Toggle(isOn: Binding(get: { model.selected.contains(row.id) }, set: { if $0 { model.selected.insert(row.id) } else { model.selected.remove(row.id) } })) {
                        VStack(alignment: .leading) {
                            Text(row.target.name).font(.caption)
                            Text(row.blocked ?? "\(DiskInfo.format(row.bytes)) · \(row.items.count) itens").font(.caption2)
                        }
                    }.disabled(row.blocked != nil)
                }
                Button("Limpar selecionados") { model.clean() }.disabled(model.selected.isEmpty)
                Button("Desfazer última limpeza") { model.undo() }
                Divider(); Text("Somente informativo — nunca limpo").bold()
                ForEach(model.info, id: \.0) { path, bytes in
                    HStack { Text("\(path) · \(DiskInfo.format(bytes))").font(.caption); Spacer(); Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([home.appendingPathComponent(path)]) } }
                }
                Divider(); TextField("Meta em GB", text: $model.meta)
                Toggle("Vigilância (a cada 3 horas, só notifica)", isOn: $model.watching)
                Button("Salvar ajustes") { model.save() }
                Text(model.message).font(.caption).textSelection(.enabled)
                Button("Sair") { NSApp.terminate(nil) }
            }.padding()
        }.frame(width: 560, height: 680)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let popover = NSPopover()
    let model = Model()
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "Disco Seguro")
        item.button?.target = self; item.button?.action = #selector(toggle)
        popover.behavior = .transient; popover.contentViewController = NSHostingController(rootView: ContentView(model: model))
        model.refresh()
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
}
if CommandLine.arguments.count > 1 {
    do { try cli(Array(CommandLine.arguments.dropFirst())) } catch { print("Erro: \(error.localizedDescription)"); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.accessory); app.delegate = delegate; app.run()
}
