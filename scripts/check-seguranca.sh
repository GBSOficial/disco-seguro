#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if grep -rnE 'URLSession|removeItem|rm -|-delete|sh -c|zsh -c|osascript|curl|Network\.framework' Sources/; then
  echo 'Falha: operação proibida encontrada.'; exit 1
else
  status=$?
  if [[ "$status" != 1 ]]; then exit "$status"; fi
fi
echo 'Verificação de segurança aprovada.'
