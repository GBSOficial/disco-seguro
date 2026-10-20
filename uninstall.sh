#!/bin/bash
set -euo pipefail
# A desinstalação também preserva os arquivos na Lixeira.
APP="$HOME/Applications/Disco Seguro.app"
if [[ -x "$APP/Contents/MacOS/DiscoSeguro" ]]; then
  "$APP/Contents/MacOS/DiscoSeguro" vigilancia desligar
fi
/usr/bin/swift - "$HOME" <<'SWIFT'
import Foundation
protocol Trasher { func trash(_ url: URL) throws }
struct SystemTrasher: Trasher {
    func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}
let trasher: any Trasher = SystemTrasher()
let home = URL(fileURLWithPath: CommandLine.arguments[1])
for path in ["Library/LaunchAgents/com.biel.disco-seguro.vigia.plist", "Applications/Disco Seguro.app", ".local/bin/disco-seguro", "Library/Application Support/DiscoSeguro"] {
    let url = home.appendingPathComponent(path)
    if FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
        try trasher.trash(url)
    }
}
SWIFT
