# Handoff · Sync Master · 2026-08-26

## Goal
Adicionar ao Sync Master uma opção de instalação de utilitários de gerenciamento via winget
(WizTree, Sysinternals, etc.), commitada e no ar. **Concluído e empurrado.**

## State
- HEAD: `d921173` (pushed; branch em sincronia com `origin/master`)
- Live state: `origin` foi corrigido para `https://github.com/Codyte/Sync.git` — o GitHub avisava
  que `Sync15` mudou de nome e o push só passava por redirecionamento. **A outra máquina ainda
  aponta para o nome velho.** Nada rodando, nada em estado não-padrão neste repo.
- Done: 3 commits — `a2417bb` (retarget dos 2 testes de ativação), `f1ced43` (o menu novo),
  `d921173` (mapas navindex). Suite **200/200**, gate de pre-commit OK nos três.
- Done: integrados 35 commits da outra máquina antes de commitar (launcher renomeado
  `Sync_MasterV15.ps1` → `Sync_Master.ps1`, `PowerShellUpdate.psm1` e `Otimizacao.psm1`
  reescritos, `install.ps1` e `.github/workflows/release.yml` novos).
- In progress: nada mid-flight.

## Decisions (and why)
- **Reusar `Invoke-WingetInstall` em vez de escrever chamada winget nova** — ele já trata os três
  tropeços: winget ausente, `--accept-*-agreements` e `$LASTEXITCODE` (exe nativo com exit ≠ 0 não
  lança exceção). Mesma lógica para `Parse-Selection`, que já fazia `"1 3 5-7"`.
- **Catálogo é dado, não código** — `Get-CatalogoFerramentas` devolve tabela; acrescentar
  utilitário é uma linha. Mesmo padrão do `Menu.psm1`, que o repo já tinha escolhido.
- **`Id` do catálogo tem que ser 1..N contíguo** — o menu passa `Parse-Selection -Max Count` e
  depois casa por `Id`; Id furado selecionaria a ferramenta errada **em silêncio**. Tem teste
  travando isso, é o invariante que justifica o arquivo de teste existir.
- **Não criei README separado do módulo** — o cabeçalho do `Ferramentas.psm1` já documenta como
  acrescentar, e o teste é quem garante. Um segundo lugar só criaria divergência.
- **Rejeitado: `--no-verify`** para passar pelo gate. E rejeitado remover o ativador MAS para
  deixar a suite verde — o dono decidiu que fica (ver `standing.md`); quem estava desatualizado
  eram os testes.
- **Testes retargetados, não apagados** — `tests/Menu.Tests.ps1` e `tests/Manifest.Tests.ps1`
  agora afirmam o contorno do ativador (oculto, não exportado, guardado) em vez da sua ausência.
- **Descartado de propósito**: a modificação local de `Sync Master.lnk` (alteração incidental do
  Windows num arquivo que o remoto apagou, trocado por `Sync Master.cmd` + `install.ps1`) e uma
  regeneração de navindex calculada sobre o código pré-merge.
- **`--map-only` no navindex** — refazer headers tocaria arquivo que a outra máquina acabou de
  escrever, por nada. Só os 3 mapas + árvore raiz; 0 headers.

## Next steps (ordered)
1. Nada bloqueante — a entrega fechou. Se voltar ao assunto, o degrau natural é
   **`--disable-interactivity` no `Invoke-WingetInstall`**: hoje não está lá (os dois `--accept-*`
   cobrem os prompts realistas), mas prompt inesperado ainda penduraria o menu inteiro. Mudança
   compartilhada com o menu do PowerShell, então precisa dos testes dos dois.
2. Corrigir o `origin` na outra máquina: `git remote set-url origin https://github.com/Codyte/Sync.git`.
3. Se quiser mais utilitários no menu: uma linha em `Get-CatalogoFerramentas`, conferindo o
   `PacoteId` com `winget show --id <id> --exact` antes (`MartiCliment.UniGetUI` **não** existe
   estável — o id certo é `Devolutions.UniGetUI`).

## Key files
- `modules/Ferramentas.psm1` — o módulo novo; catálogo, render, `Install-Ferramenta`, menu.
- `tests/Ferramentas.Tests.ps1` — 8 testes; o de `Id` contíguo é o que importa.
- `modules/Menu.psm1` — entrada `16` na tabela do menu principal.
- `SyncMaster.psd1` — `NestedModules` + `FunctionsToExport`.
- `modules/__navi__.md` e `tests/__navi__.md` — mapas das duas pastas que os próximos passos tocam.

## Open / blockers
- **Nenhum bloqueio.** Um débito registrado: `Ativacao.psm1` e a auditoria de 12/08 se contradizem
  por construção agora (a auditoria removeu o ativador, o dono re-adicionou). Está resolvido no
  nível dos testes e anotado em `standing.md` — não reabrir sem motivo novo.
- Trabalho feito de uma sessão que nasce na **sessão 0** do Windows (VS Code tunnel): winget com
  instalador MSIX falha ali com `0x80070520`. Não afeta este repo (o Sync Master roda interativo),
  mas afeta qualquer agente que tente instalar pacote daqui.

## Skills
- navindex

## Effort
**Baixo** para o passo 1 — é mudança de uma flag num helper de 20 linhas, com dois testes já
existentes cobrindo os chamadores. Sobe para **médio** se o `--disable-interactivity` fizer o
winget recusar em máquina com versão antiga (a flag exige winget ≥ 1.4), porque aí vira detecção
de versão em runtime. Raciocínio não é o gargalo aqui: o custo real é a suite Pester (~8 s por
commit por causa do gate) e o round-trip do winget.
