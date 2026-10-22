#!/bin/bash
set -euo pipefail
# A desinstalação também preserva os arquivos na Lixeira.
for APP in "/Applications/Disco Seguro.app" "$HOME/Applications/Disco Seguro.app"; do
  if [[ -x "$APP/Contents/MacOS/DiscoSeguro" ]]; then
    "$APP/Contents/MacOS/DiscoSeguro" vigilancia desligar
  fi
done
pkill -x DiscoSeguro 2>/dev/null || true
osascript -e 'tell application "System Events" to delete (every login item whose name is "Disco Seguro")' >/dev/null 2>&1 || true
/usr/bin/swift - "$HOME" <<'SWIFT'
import Foundation
protocol Trasher { func trash(_ url: URL) throws }
struct SystemTrasher: Trasher {
    func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}
let trasher: any Trasher = SystemTrasher()
let home = URL(fileURLWithPath: CommandLine.arguments[1])
for path in ["Library/LaunchAgents/com.gbsoficial.disco-seguro.vigia.plist", "Applications/Disco Seguro.app", ".local/bin/disco-seguro", "Library/Application Support/DiscoSeguro"] {
    let url = home.appendingPathComponent(path)
    if FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
        try trasher.trash(url)
    }
}
let system = URL(fileURLWithPath: "/Applications/Disco Seguro.app")
if FileManager.default.fileExists(atPath: system.path) { try trasher.trash(system) }
SWIFT
