import Foundation
import Darwin
public struct Watcher {
    public let home: URL
    public init(home: URL) { self.home = home }
    public var plist: URL { home.appendingPathComponent("Library/LaunchAgents/com.gbsoficial.disco-seguro.vigia.plist") }
    private func launch(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        // Only our own agent, never caller-supplied launchctl arguments.
        if command == "bootstrap" { process.arguments = ["bootstrap", "gui/\(getuid())", plist.path] }
        else { process.arguments = ["bootout", "gui/\(getuid())/com.gbsoficial.disco-seguro.vigia"] }
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SafetyError.denied("launchctl falhou: \(process.terminationStatus)") }
    }
    public func setEnabled(_ enabled: Bool, binary: URL) throws {
        var config = try Config.load(home: home)
        let guarder = PathGuard(home: home)
        if enabled {
            try guarder.prepareDirectory(plist.deletingLastPathComponent())
            try guarder.validate(plist, root: plist.deletingLastPathComponent())
            let data: [String: Any] = ["Label": "com.gbsoficial.disco-seguro.vigia", "ProgramArguments": [binary.path, "vigiar"], "StartInterval": config.intervaloHoras * 3600, "RunAtLoad": false]
            try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0).write(to: plist, options: .atomic)
            try launch("bootstrap")
        } else if PathGuard.exists(plist) {
            try guarder.validate(plist, root: plist.deletingLastPathComponent())
            try launch("bootout")
            _ = try SystemTrasher().trash(plist)
        }
        config.vigilancia = enabled
        try config.save(home: home)
    }
}
