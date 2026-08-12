# Handoff · Sync Master · 2026-08-12

## Goal
Continuar a auditoria recursiva e orientada por risco do Sync Master para Windows 10/11 desktop x64, com sessão elevada.

## State
- HEAD: 736e4c0
- Done: `Otimizacao.psm1` agora preserva startups em falhas/colisões (`8e4cb2b`), limita limpeza a TEMP absoluto fora da raiz (`ae10108`) e propaga falhas de escrita/backup do Registro (`95789c1`).
- Done: removidos BCDEDIT livre (`5393b02`), ativador remoto (`ec51ba1`), clonagem bruta por `dd` (`b7df534`) e executor remoto WinUtil (`736e4c0`).
- Done: speedtest não instala módulos arbitrários e exige confirmação para o pacote exato da Ookla (`59fd561`); pseudo-otimização QoS removida (`e7d6859`); parser/porta TCP limitados (`e929550`).
- Done: monitor de hardware rejeita ciclo zero e intervalo agressivo (`3781dac`).
- Done: gate final em `736e4c0`: 165 testes, 0 falhas; PSScriptAnalyzer 0 erros e 10 warnings preexistentes. Smokes direcionados passaram no Windows PowerShell 5.1.19041 do host Windows 10.
- In progress: nenhuma edição de produção; `master` sincronizado com `origin/master`. Este handoff/arquivo ainda precisa ser commitado.

## Decisions (and why)
- Remover pontes genéricas para código remoto em vez de manter hash opcional — hash calculado após download não autentica origem e a utilidade já existe fora do produto.
- Remover BCDEDIT livre, clonagem `dd` e QoS enganoso em vez de criar allowlists/abstrações — alto risco, baixo valor e sem contrato confiável para Windows desktop comum.
- Speedtest mantém somente CLI oficial já instalada ou winget com consentimento — cadeia de confiança curta e funcionalidade preservada.
- Para operações destrutivas, colisão/falha preserva o original e avisa; nunca renomear/apagar como fallback de “desabilitar”.

## Next steps (ordered)
1. Ler `__navi__.md`, `modules/__navi__.md` e auditar comandos nativos que ainda registram sucesso sem checar exit code: `Menu-Rede` (`ipconfig`/`netsh`) e energia/hibernação em `Sync_Master.ps1`/`Otimizacao.psm1`; usar AST/mocks, nunca alterar a rede real.
2. Revisar ativação oficial: validar formato da product key, resolver `slmgr.vbs` via diretório do Windows e checar exit code sem expor a chave em logs.
3. Auditar `Arquivos.psm1` por exclusões/reciclagem/permissões e `Criar-App` pelo caminho ps2exe hardcoded e falso sucesso em exit code não zero.
4. Atualizar NAV após mover linhas, rodar `tools/Run-Checks.ps1`, smoke 5.1 quando relevante, commit e push por lote pequeno.

## Key files
- `__navi__.md` — árvore global atualizada; ponto inicial obrigatório.
- `modules/__navi__.md` — mapa exato de Rede, Hardware, Otimização e Arquivos.
- `modules/Rede.psm1:287` — menu com comandos nativos ainda sem verificação de resultado.
- `modules/Otimizacao.psm1:94` — `powercfg` ainda anuncia sucesso sem checar exit code.
- `Sync_Master.ps1:721` — otimizações avançadas/hibernação; `Sync_Master.ps1:1091` — `Criar-App`.
- `modules/Ativacao.psm1:7` — somente fluxos oficiais restantes.
- `tools/Run-Checks.ps1` — gate completo.

## Open / blockers
- Nenhum bloqueio. Não executar alterações reais de rede, registro, serviços, energia ou hardware durante testes.

## Skills
- ponytail: rastrear chamadores e aplicar a menor correção causal, sem dependências/abstrações especulativas.
- navindex: ler mapas antes de explorar e regenerar cabeçalhos/mapas após mover linhas ou símbolos.

## Effort
medium para o passo 1 — vários comandos nativos e mensagens/logs compartilham o mesmo risco; subir para high se a semântica de exit code divergir entre Windows 10 e 11.
