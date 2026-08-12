# Handoff · Sync Master · 2026-08-12

## Goal
Turbinar o Sync Master com uma auditoria recursiva, prática e orientada por risco, buscando bugs e incompatibilidades relevantes para Windows desktop comum.

## State
- HEAD: 91a53e4
- Done: instalador remoto idempotente; README documenta duas URLs IRM; relançamento PS 5.1 -> PS 7 corrigido com `-EncodedCommand`, preservando caminhos e sem matar o host.
- Done: suíte completa em `91a53e4`: 137 testes, 0 falhas; PSScriptAnalyzer 0 erros e 10 warnings preexistentes.
- Done: inventário aproximado encontrou 123 funções; 45 são mencionadas nominalmente nos testes e 78 não são. Isso indica lacunas, mas não mede cobertura real.
- In progress: nenhuma edição pendente; árvore limpa e `master` sincronizado com `origin/master` no momento deste handoff.

## Decisions (and why)
- Foco em Windows 11 x64 desktop; aceitar Windows 10 quando vier quase de graça — maximiza retorno.
- Não investir em Windows Server, Server Core, Windows legado ou combinações raras — não são o produto pretendido.
- Auditar filhos antes dos chamadores e por risco, não por ordem textual — corrige causas compartilhadas uma vez.
- Prioridade: bootstrap/Core -> Sync/Backup -> alterações administrativas -> Rede/Hardware -> menus.
- Operação sem `winget`, Store, internet ou admin deve falhar de forma controlada somente quando esse cenário for comum; não construir fallbacks para casos raros.
- Itens de alto risco já identificados: `Ativar-Crack` executa script remoto com hash opcional; opção BCDEDIT aceita argumentos livres. Avaliar remoção/restrição antes de expandir recursos.

## Next steps (ordered)
1. Ler `__navi__.md`, `modules/__navi__.md`, `modules/Core.psm1` e todos os chamadores de cada função de Core; criar uma tabela curta de risco/dependências antes de editar.
2. Auditar `Core.psm1` função por função: PS 5.1/7 quando relevante, admin/usuário, caminhos, erros, idempotência e efeitos externos. Corrigir apenas achados concretos e adicionar regressões em `tests/`.
3. Rodar `tools/Run-Checks.ps1`, smoke test direcionado e atualizar NAV após cada lote pequeno; commit/push somente com gate verde.
4. Seguir para `Sync.psm1` e `Backup.psm1`, priorizando validação de origem/destino, exit codes, simulação e prevenção de perda de dados.
5. Depois revisar operações administrativas em `Otimizacao.psm1` e `Sync_Master.ps1`; só então Rede/Hardware. Menus ficam por último.
6. Considerar um `AUDIT.md` apenas se a primeira onda mostrar que o estado não cabe claramente nos commits/testes; evitar burocracia antecipada.

## Key files
- `__navi__.md` — índice global; ler primeiro e regenerar após mudanças estruturais.
- `modules/__navi__.md` — mapa exato das 103 funções modulares.
- `modules/Core.psm1` — primeira onda, helpers compartilhados de dados, logs, diretórios e privilégios.
- `tests/ModuleLoading.Tests.ps1`, `tests/Sync.Tests.ps1`, `tests/Backup.Tests.ps1` — contratos atuais próximos das primeiras ondas.
- `tools/Run-Checks.ps1` — gate: PSScriptAnalyzer + Pester.
- `New-ScriptFlowTree.ps1`, `README-FlowTree.md` — análise AST do fluxo; usar para localizar chamadores/menus sem executar operações perigosas.
- `modules/Ativacao.psm1:7` — execução remota a reconsiderar.
- `Sync_Master.ps1:996` — entrada BCDEDIT livre a reconsiderar.

## Open / blockers
- Nenhum bloqueio. Não criar suporte a Server/legado durante a auditoria.
- Não chamar operações destrutivas reais nos testes; usar mocks, `-WhatIf`, `-Simular` ou diretórios temporários isolados.

## Skills
- ponytail: aplicar em toda correção; ler fluxo e chamadores primeiro, depois escolher a menor correção da causa raiz, sem dependências ou abstrações especulativas.
- navindex: ler os mapas antes de explorar; após mover linhas/símbolos, atualizar o cabeçalho do arquivo e os `__navi__.md` afetados, incluindo-os no commit.
- handoff: usar apenas ao trocar/limpar sessão ou quando ainda restarem várias ondas; arquivar o ativo e salvar HEAD, testes, decisões e próximo passo, sem transformar o handoff em diário.

## Effort
medium para o passo 1 — exige rastrear muitos chamadores e distinguir risco real de casos raros; subir para high somente se uma operação destrutiva ou comportamento do Windows contradizer a documentação/testes.
