#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
mkdir -p "$HOME/Applications"
if [[ -e "$HOME/Applications/Disco Seguro.app" ]]; then
  echo 'Já existe uma instalação. Desinstale-a antes de continuar.'; exit 1
fi
ditto 'build/Disco Seguro.app' "$HOME/Applications/Disco Seguro.app"
if [[ -d "$HOME/.local/bin" ]]; then
  ln -s "$HOME/Applications/Disco Seguro.app/Contents/MacOS/DiscoSeguro" "$HOME/.local/bin/disco-seguro"
else
  echo 'Dica: crie ~/.local/bin e adicione ao PATH para usar disco-seguro no terminal.'
fi
