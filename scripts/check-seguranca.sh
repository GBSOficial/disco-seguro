#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if grep -rnE 'URLSession|removeItem|rm -|-delete|sh -c|zsh -c|osascript|curl|Network\.framework|kill[[:space:]]*\(|killall|pkill|powermetrics|sudo' Sources/; then
  echo 'Falha: operação proibida encontrada.'; exit 1
else
  status=$?
  if [[ "$status" != 1 ]]; then exit "$status"; fi
fi
# A vigilância existente usa launchctl; Saúde nunca cria subprocessos.
if grep -rnE 'Process[[:space:]]*\(|import[[:space:]]+Network|signal[[:space:]]*\(' Sources/DiscoCore/Health/ Sources/DiscoSeguro/HealthUI.swift; then
  echo 'Falha: operação proibida na Saúde.'; exit 1
else
  status=$?
  if [[ "$status" != 1 ]]; then exit "$status"; fi
fi
echo 'Verificação de segurança aprovada.'
