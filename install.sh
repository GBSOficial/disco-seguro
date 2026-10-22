#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
# /Applications quando dá pra gravar (aparece no Launchpad); senão ~/Applications.
DEST=/Applications
[[ -w $DEST ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
if [[ -e "/Applications/Disco Seguro.app" || -e "$HOME/Applications/Disco Seguro.app" ]]; then
  echo 'Já existe uma instalação. Desinstale-a antes de continuar.'; exit 1
fi
ditto 'build/Disco Seguro.app' "$DEST/Disco Seguro.app"
if [[ -d "$HOME/.local/bin" ]]; then
  ln -s "$DEST/Disco Seguro.app/Contents/MacOS/DiscoSeguro" "$HOME/.local/bin/disco-seguro"
else
  echo 'Dica: crie ~/.local/bin e adicione ao PATH para usar disco-seguro no terminal.'
fi
read -r -p 'Abrir o Disco Seguro ao ligar o Mac? [s/N] ' abrir || true
if [[ ${abrir:-} == [sS]* ]]; then
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$DEST/Disco Seguro.app\", hidden:false}" >/dev/null
  echo 'Adicionado aos itens de início de sessão.'
fi
open "$DEST/Disco Seguro.app"
