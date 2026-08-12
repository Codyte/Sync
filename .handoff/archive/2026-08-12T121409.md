# Handoff · Sync Master · 2026-08-12

## Goal
Continuar a auditoria recursiva e orientada por risco do Sync Master para Windows 10 e 11 desktop x64, assumindo execução elevada.

## State
- HEAD: 7dfc8ff
- Done: `Core.psm1` auditado; criação de data dir e `Ensure-Dir` agora falham se o caminho não for diretório ou não puder ser criado (`9c9814f`).
- Done: `Sync.psm1` corrigido em quatro lotes: subpastas comuns de perfil não perdem arquivos por autoexclusão (`626fed3`); destino inexistente é normalizado antes do guard de aninhamento (`71f1b38`); amostragem para tuning para em `LimiteArquivos + 1` e distingue limite exato (`e0d4100`); horário agendado aceita só `00:00..23:59` (`7dfc8ff`).
- Done: `Backup.psm1` inspecionado; round-trip, origem/ZIP ausentes e overwrite já cobertos, sem achado concreto que justificasse edição.
- Done: gate final em `7dfc8ff`: 143 testes, 0 falhas; PSScriptAnalyzer 0 erros e 10 warnings preexistentes. Smokes direcionados passaram em Windows PowerShell 5.1.19041 no host Windows 10.
- In progress: nenhuma edição de produção pendente; `master` sincronizado com `origin/master`. Apenas este handoff/arquivo de arquivo ainda precisa ser commitado após a gravação.

## Decisions (and why)
- Windows 10 e 11 desktop x64 são alvos de primeira classe; Server/legado continuam fora — pedido atual do usuário e standing decision atualizada.
- Sessão elevada é condição inicial; não gastar auditoria em fluxos sem admin — orientação explícita do usuário.
- PowerShell 7 continua preferencial; validar PS 5.1 apenas onde bootstrap ou fluxo automatizado já depende dele.
- Corrigir um guard compartilhado por vez, com regressão antes/depois — reduz escopo e cobre todos os chamadores.
- Não alterar ZIP sem falha demonstrável; a proteção/extrator nativo já atende o fluxo atual.
- Não expandir nesta onda para resolução física de junctions/symlinks; falta um caso reproduzido e isso exigiria solução Windows específica maior.

## Next steps (ordered)
1. Ler `modules/__navi__.md`, `modules/Otimizacao.psm1`, `tests/Otimizacao.Tests.ps1` e chamadores antes de editar; montar risco curto de registro, startups, limpeza, storage e serviços.
2. Auditar primeiro `Set-DWord`, `Backup-Registro`, `Clean-Temp`, `Disable-/Enable-StartupByNumber` e seus efeitos/rollback em Windows 10/11 elevado; usar mocks e diretórios temporários, nunca alterações reais.
3. Depois revisar operações administrativas em `Sync_Master.ps1`, começando pela entrada BCDEDIT livre; decidir restrição/remoção com teste.
4. Revisar `Ativacao.psm1` (script remoto/hash opcional) e `Clonar-Disco` (semântica de volume/disco e `dd`) antes de manter esses recursos.
5. Seguir para Rede/Hardware e menus; atualizar NAV, rodar `tools/Run-Checks.ps1`, commit e push em cada lote pequeno.

## Key files
- `__navi__.md` — índice global atualizado.
- `modules/__navi__.md` — mapa das funções; ponto inicial obrigatório.
- `modules/Otimizacao.psm1` — próxima onda administrativa.
- `tests/Otimizacao.Tests.ps1` — contratos existentes e local provável das regressões.
- `Sync_Master.ps1:1011` — fluxo BCDEDIT com argumentos livres.
- `modules/Ativacao.psm1:7` — execução remota a reavaliar.
- `modules/Backup.psm1:125` — clonagem por `dd` a reavaliar.
- `tools/Run-Checks.ps1` — gate completo.

## Open / blockers
- Nenhum bloqueio.
- Riscos ainda abertos: BCDEDIT livre, ativador remoto e clonagem por `dd`; não executar nenhum deles durante testes.

## Skills
- ponytail: ler fluxo/chamadores e aplicar a menor correção causal, sem dependências ou abstrações especulativas.
- navindex: ler mapas antes de explorar e regenerar cabeçalhos/mapas após mover linhas ou símbolos.

## Effort
medium para o passo 1 — helpers administrativos têm efeitos externos e vários chamadores; subir para high se comportamento real do Windows contradizer os contratos ou exigir decisão destrutiva.
