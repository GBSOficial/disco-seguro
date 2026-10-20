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
struct Row: Identifiable {
    let id: String
    let title: String
    let ids: [String]
    let bytes: Int64
    let count: Int
    let blocked: String?
}
let ownerNames = ["com.google.Chrome": "Chrome", "com.microsoft.edgemac": "Edge", "com.brave.Browser": "Brave", "org.mozilla.firefox": "Firefox", "company.thebrowser.Browser": "Arc", "com.spotify.client": "Spotify", "com.adobe.LightroomClassicCC7": "Lightroom", "com.adobe.Photoshop": "Photoshop", "com.openai.codex": "Codex", "com.apple.dt.Xcode": "Xcode"]
func friendlyName(_ path: String) -> String {
    let names = ["Library/Caches/Google/Chrome": "Cache do Chrome", "Library/Caches/Microsoft Edge": "Cache do Edge", "Library/Caches/BraveSoftware": "Cache do Brave", "Library/Caches/Firefox": "Cache do Firefox", "Library/Caches/Arc": "Cache do Arc", "Library/Caches/com.spotify.client": "Cache do Spotify", "Library/Caches/Adobe Camera Raw 2": "Cache do Camera Raw", "Library/Caches/claude-cli-nodejs": "Cache do Claude Code", "Library/Caches/Codex": "Cache do Codex", "Library/Caches/pip": "Cache do pip", "Library/Caches/pnpm": "Cache do pnpm", "Library/Caches/Yarn": "Cache do Yarn", "Library/Caches/Homebrew": "Cache do Homebrew", "Library/Caches/go-build": "Cache do Go", "Library/Caches/CocoaPods": "Cache do CocoaPods", ".npm/_cacache": "Cache do npm", ".cache/uv": "Cache do uv", "Library/Developer/Xcode/DerivedData": "Xcode DerivedData", "Library/Logs": "Logs com mais de 7 dias", "Downloads": "Downloads", ".codex/sessions": "Conversas do Codex", ".claude/projects": "Projetos do Claude Code", ".cache/huggingface/hub": "Modelos Hugging Face", ".ollama": "Ollama", ".lmstudio": "LM Studio", "Library/Containers/com.docker.docker": "Docker", "Library/Application Support/MobileSync/Backup": "Backups de iPhone", "Library/Developer/CoreSimulator": "Simuladores iOS", "Movies": "Filmes", "Library/Application Support/Claude/vm_bundles": "Máquina virtual do Claude"]
    if let name = names[path] { return name }
    if path.hasSuffix(".ShipIt") { return "Atualização baixada · " + (path.split(separator: "/").last.map(String.init) ?? path) }
    return path
}
func rows(_ results: [ScanResult]) -> [Row] {
    let crash = results.filter { $0.target.name.contains("/Crashpad/") }
    var list = results.filter { !$0.target.name.contains("/Crashpad/") }.map { r in
        Row(id: r.id, title: friendlyName(r.target.name), ids: [r.id], bytes: r.bytes, count: r.items.count, blocked: r.blocked.map { b in ownerNames.reduce(b) { $0.replacingOccurrences(of: $1.key, with: $1.value) } })
    }
    let usable = crash.filter { $0.blocked == nil }
    list.append(Row(id: "crash", title: "Relatórios de crash", ids: usable.map(\.id), bytes: usable.reduce(0) { $0 + $1.bytes }, count: usable.reduce(0) { $0 + $1.items.count }, blocked: nil))
    return list.filter { $0.blocked != nil || $0.count > 0 }.sorted { $0.bytes > $1.bytes }
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
    @Published var loading = false
    @Published var showInfo = false
    @Published var showSettings = false
    var selectedBytes: Int64 { results.filter { selected.contains($0.id) && $0.blocked == nil }.reduce(0) { $0 + $1.bytes } }
    func refresh() {
        do {
            let config = try Config.load(home: home), disk = try DiskInfo(home: home)
            meta = String(Int(config.metaGB)); watching = config.vigilancia; free = disk.free; total = disk.total
        } catch { message = error.localizedDescription }
        guard !loading else { return }
        loading = true
        let apps = running()
        Task.detached {
            let scanned = Targets.all(home: home).map { Scanner(home: home).scan($0, running: apps) }
            let sizes = Targets.informational.map { ($0, Scanner(home: home).informativeSize(home.appendingPathComponent($0))) }
            await MainActor.run {
                self.results = scanned
                self.selected = Set(scanned.filter { $0.blocked == nil && !$0.items.isEmpty }.map(\.id))
                self.info = sizes.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
                self.loading = false
            }
        }
    }
    func clean() {
        // Fresh plan is the exact snapshot confirmed by the user.
        let plan = scanAll().filter { selected.contains($0.id) && $0.blocked == nil && !$0.items.isEmpty }
        guard !plan.isEmpty else { message = "Nada selecionado para limpar."; return }
        let alert = NSAlert(); alert.messageText = "Enviar para a Lixeira?"
        alert.informativeText = rows(plan).map { "\($0.title): \(DiskInfo.format($0.bytes))" }.joined(separator: "\n") + "\n\nTotal: " + DiskInfo.format(plan.reduce(0) { $0 + $1.bytes }) + "\nDá pra desfazer depois."
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160)); text.isEditable = false
        text.string = plan.flatMap(\.items).map { "\($0.url.path) — \(DiskInfo.format($0.bytes))" }.joined(separator: "\n")
        let scroll = NSScrollView(frame: text.frame); scroll.documentView = text; scroll.hasVerticalScroller = true; alert.accessoryView = scroll
        alert.addButton(withTitle: "Enviar para a Lixeira"); alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { _ = try Cleaner(home: home).execute(plan, running: running); message = "Pronto! Itens enviados para a Lixeira."; refresh() } catch { message = error.localizedDescription }
    }
    func undo() { do { let count = try Undo(home: home).latest(running: running); message = "\(count) itens restaurados."; refresh() } catch { message = error.localizedDescription } }
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
    var metaBytes: Double { (Double(model.meta) ?? 30) * 1e9 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Disco Seguro").font(.headline)
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Analisar de novo")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(DiskInfo.format(model.free)) livres de \(DiskInfo.format(model.total))").font(.subheadline.bold())
                ProgressView(value: model.total > 0 ? Double(model.total - model.free) / Double(model.total) : 0).tint(Double(model.free) < metaBytes ? .orange : .accentColor)
                Text(Double(model.free) < metaBytes ? "Abaixo da meta de \(model.meta) GB" : "Dentro da meta de \(model.meta) GB").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Lixo seguro (vai para a Lixeira)").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows(model.results)) { row in
                        let on = !row.ids.isEmpty && row.ids.allSatisfy { model.selected.contains($0) }
                        Toggle(isOn: Binding(get: { on }, set: { v in for id in row.ids { if v { model.selected.insert(id) } else { model.selected.remove(id) } } })) {
                            HStack {
                                Text(row.title).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(row.blocked ?? DiskInfo.format(row.bytes)).font(.caption).foregroundStyle(row.blocked == nil ? Color.secondary : Color.orange)
                            }
                        }.disabled(row.blocked != nil || row.ids.isEmpty)
                    }
                    if !model.loading && rows(model.results).isEmpty { Text("Nada para limpar agora.").font(.caption).foregroundStyle(.secondary) }
                    DisclosureGroup("Só informativo (nunca limpo)", isExpanded: $model.showInfo) {
                        ForEach(model.info, id: \.0) { path, bytes in
                            HStack {
                                Text(friendlyName(path)).font(.caption)
                                Spacer()
                                Text(DiskInfo.format(bytes)).font(.caption).foregroundStyle(.secondary)
                                Button { NSWorkspace.shared.activateFileViewerSelecting([home.appendingPathComponent(path)]) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Mostrar no Finder")
                            }
                        }
                    }.font(.caption.bold()).padding(.top, 6)
                    DisclosureGroup("Ajustes", isExpanded: $model.showSettings) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Meta (GB livres)").font(.caption); TextField("30", text: $model.meta).frame(width: 60) }
                            Toggle("Vigilância: avisa a cada 3 h (nunca limpa)", isOn: $model.watching).font(.caption)
                            Button("Salvar ajustes") { model.save() }
                        }.padding(.top, 4)
                    }.font(.caption.bold())
                }.padding(.trailing, 6)
            }
            Divider()
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            HStack {
                Button("Limpar \(DiskInfo.format(model.selectedBytes))") { model.clean() }.buttonStyle(.borderedProminent).disabled(model.selectedBytes == 0 || model.loading)
                Button("Desfazer última") { model.undo() }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(14)
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
        let host = NSHostingController(rootView: ContentView(model: model))
        host.sizingOptions = []
        popover.behavior = .transient; popover.contentViewController = host
        model.refresh()
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        // Fit the popover inside the visible screen area below the menu bar.
        let visible = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: 400, height: min(560, visible - 40))
        model.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}
if CommandLine.arguments.count > 1 {
    do { try cli(Array(CommandLine.arguments.dropFirst())) } catch { print("Erro: \(error.localizedDescription)"); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.accessory); app.delegate = delegate; app.run()
}
