# Disco Seguro

App de barra de menus e CLI para macOS 14+, sem dependências externas e sem rede.
A limpeza usa exclusivamente a Lixeira, com prévia e confirmação. Só caches da
lista fixa, relatórios Crashpad e arquivos de log com mais de sete dias são elegíveis.
Links simbólicos são recusados; apps donos abertos bloqueiam seus caches.
Downloads, sessões e modelos de IA são apenas informativos.

```text
./build.sh                  # compila, empacota e assina ad-hoc
./install.sh                # instalação manual opcional em ~/Applications
DiscoSeguro status
DiscoSeguro analisar
DiscoSeguro limpar          # só simula
DiscoSeguro limpar --executar       # prévia e pergunta obrigatória
DiscoSeguro limpar --executar --sim # prévia, sem pergunta
DiscoSeguro desfazer
DiscoSeguro meta 30
DiscoSeguro vigilancia ligar
DiscoSeguro vigilancia desligar
DiscoSeguro vigiar
DiscoSeguro ajuda
```

Sem argumentos, o binário abre o app. O link `disco-seguro` é criado pelo instalador
somente quando `~/.local/bin` existe. Nenhum arquivo de shell é editado.
Vigilância vem desligada; quando ativada, só notifica, a cada três horas por padrão.
Autorize as notificações nos ajustes do app. O agente usa o binário instalado;
não mova o app enquanto a vigilância estiver ligada.

Configuração e manifestos JSON ficam em `~/Library/Application Support/DiscoSeguro`.
Desfazer restaura a última limpeza com itens pendentes, apenas quando o original
não existe e o arquivo ainda está na Lixeira. Não recria pastas ausentes nem sobrescreve.
Esvaziar a Lixeira impede a recuperação. A desinstalação (`./uninstall.sh`) também
manda os componentes para a Lixeira, incluindo os manifestos.

Validação: `swift build -c release`, `swift test`, `./build.sh` e
`./scripts/check-seguranca.sh`. Testes usam FakeTrasher e fixtures em `.build/test-homes`.
A varredura e a prévia não gravam configuração nem movem arquivos. Tamanhos usam
espaço alocado e podem diferir do ganho real por compressão, clones e snapshots APFS.
Caminhos e apps são revalidados antes de mover; mudanças concorrentes do sistema
não podem ser eliminadas completamente pelas APIs de caminho do FileManager.

Neste ambiente restrito, o backend padrão do Swift 6.4 falhou ao gerar o dSYM.
`build.sh` usa `--build-system native` e caches locais; esse backend está obsoleto
no Swift 6.4, mas compilou com sucesso. Para reproduzir os testes neste ambiente:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --build-system native \
  --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
  --security-path "$PWD/.build/security" --manifest-cache local
```
