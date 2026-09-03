# Handoff · Sync Master · 2026-09-03

## Goal
Criar no menu WPA (2 → 2 → 6) uma opção **orquestradora**: roda a triagem inteira chamando as
funções que já existem, na ordem certa, e quando não conseguir concluir sozinha **orienta o
usuário** com o próximo passo concreto. Funções novas são bem-vindas onde faltarem.

## State
- HEAD: `559d900` (empurrado; `origin/master` em sincronia)
- Live state: nada rodando, nada em estado não-padrão. Nenhuma correção WPA foi executada nesta
  máquina — só caminhos de leitura. Relatórios de teste ficaram em
  `%LOCALAPPDATA%\SyncMaster\Relatorios\WPA\` (descartáveis).
- Done: 3 commits nesta sessão — `51615fc` (arsenal de correção), `559d900` (Win11 + 17 testes de
  comportamento + telefone + sonda ACL + estado granular). Gate **242/242**, lint 0 erros /
  11 warnings (baseline).
- In progress: nada mid-flight. O que segue é trabalho novo, já especificado abaixo.

## Decisions (and why)
- **O arsenal de correção está completo** — `/ato`, `/rilc`, `/ckms`, tokens.dat, DISM+SFC,
  `/upk`+`/cpky`, `/rearm`, `/dti`+`/atp`, serviços, e a escada guiada. Não falta verbo oficial.
  O que falta é **triagem**, não reparo. Não reabrir o reparo.
- **Nada apaga `HKLM\SYSTEM\WPA`** e o `tokens.dat` é renomeado, nunca apagado — travado por teste
  em `tests/Menu.Tests.ps1`. A árvore inchada **não encolhe** com nenhuma opção; isso é deliberado
  (sem contrato oficial de reconstrução) e o orquestrador precisa dizer isso ao usuário em vez de
  prometer faxina.
- **Testes de comportamento usam estado `$global:`** — `Mock -ModuleName` e `InModuleScope` rodam em
  session states diferentes e `$script:` não é o mesmo dos dois lados; com `$script:` o flag vazava
  entre casos e o teste passava por acidente. Suprimido no PSScriptAnalyzer com justificativa no
  topo de `tests/Wpa.Tests.ps1`. **Não "consertar" isso de volta para `$script:`.**
- **Rejeitado redistribuir o PsExec no repo** — a licença Sysinternals proíbe. Aquisição é via
  WinGet (`Microsoft.Sysinternals.PsTools`, id exato) com fallback para live.sysinternals.com, sempre
  com consentimento + validação Authenticode.
- **`Invoke-Slmgr` captura a saída** (`-Quiet`) decodificando o code page OEM. Sem isso o relatório
  sai com acento quebrado ("m�quina"). Não voltar para `Start-Process`.

## Next steps (ordered)
1. **Contagem O(1) da árvore.** `Get-WpaSample` faz `Get-ChildItem` completo; com 200k+ subchaves
   leva minutos. Trocar por
   `[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\WPA').SubKeyCount` (campo do hive,
   instantâneo; fechar o handle). **Isso também corrige um defeito real:** `Measure-WpaGrowth`
   chama `Get-WpaSample` antes e depois do `Start-Sleep`, então numa máquina inchada a janela real
   vira ~11 min enquanto o objeto informa `Seconds = 300` — o delta sai inflado e o relatório mente
   sobre o intervalo.
2. **`Get-WpaHiveSize`** — tamanho de `C:\Windows\System32\config\SYSTEM` em disco. Sinal mais
   barato que existe (normal 10–30 MB; centenas de MB confirmam o inchaço sem enumerar nada).
   Entra em `Get-WpaDiagnostic` e em `Export-WpaReport`.
3. **`Test-WpaActivatorFootprint`** — a bifurcação que decide todo o resto: canal `KMSCLIENT` em
   máquina OEM/Retail, `SoftwareLicensingService.KeyManagementServiceMachine` preenchido, e tarefas
   agendadas com cara de renovador (`Get-ScheduledTask` filtrando `KMS|activat|AutoKMS|Renew`).
   Se houver ativador vivo, reparar é tratar sintoma — volta em horas.
4. **Amostragem em `Invoke-WpaSystemProbe`.** Hoje roda `Get-Acl` **por subchave**: em 200k chaves
   são 200k chamadas, horas. Amostrar algumas centenas e rotular o resultado como amostra.
5. **`Invoke-WpaTriage` + entrada `0` no topo do menu** — o orquestrador pedido. Chama, em ordem:
   hive size → activator footprint → `Get-WpaDiagnostic` → `Measure-WpaGrowth` (janela maior) →
   opcionalmente a sonda como SYSTEM. Emite **veredito + próximo passo**: *ativador presente* /
   *crescendo agora* / *cicatriz antiga* / *licença ilegítima* / *inconclusivo, faça X*. Quando
   depender de algo que ele não pode fazer sozinho (PsExec ausente, sem elevação, sem rede),
   **orienta** em vez de falhar calado.
6. Teste de comportamento para o veredito em `tests/Wpa.Tests.ps1` (mockar os coletores, afirmar a
   conclusão de cada combinação) + navindex + gate + commit.

## Key files
- `modules/Ativacao.psm1` — tudo do WPA vive aqui (1094 linhas; header navindex no topo mapeia os 32 símbolos).
- `tests/Wpa.Tests.ps1` — testes de comportamento com mocks; o padrão `$global:WpaTeste` a seguir.
- `tests/Menu.Tests.ps1` — testes estáticos (contorno do módulo, invariantes de segurança).
- `modules/__navi__.md` e `tests/__navi__.md` — mapas das duas pastas que os passos tocam.

## First call
```bash
cd /c/Scripts/Script_Sync/Sync; echo "=== 1 git ==="; git log -3 --oneline; git status --short; echo "=== 2 navi modules ==="; sed -n '1,40p' modules/__navi__.md; echo "=== 3 header ativacao ==="; sed -n '1,45p' modules/Ativacao.psm1; echo "=== 4 sample+growth ==="; sed -n '/^function Get-WpaSample/,/^}/p' modules/Ativacao.psm1; echo "=== 5 menu topo ==="; sed -n '/--- WPA \/ PROTECAO/,/Sua escolha/p' modules/Ativacao.psm1; echo "=== 6 padrao de teste ==="; sed -n '/^Describe .Invoke-WpaGuidedRepair/,/^    }/p' tests/Wpa.Tests.ps1 | head -40
```

## Open / blockers
- **Nenhum bloqueio.** Aviso operacional: a máquina de desenvolvimento está licenciada e com árvore
  WPA pequena, então o caso extremo (centenas de milhares de subchaves) **não dá para reproduzir
  aqui** — os passos 1 e 4 têm de ser validados por teste com mock, não por execução real.
- Sessão em sessão 0 do Windows (VS Code tunnel) falha ao instalar MSIX pelo winget (`0x80070520`).
  Não afeta este repo, afeta qualquer tentativa de instalar o PsTools a partir daqui.

## Skills
- navindex

## Effort
**Médio** para o passo 1. É pouca linha, mas `Get-WpaSample` é chamado por `Get-WpaDiagnostic`,
`Measure-WpaGrowth` e `Invoke-WpaSystemProbe` — trocar a fonte da contagem sem ler os três callers
é como se ship um bug silencioso de medição. Sobe para **alto** se `SubKeyCount` divergir da
enumeração (chaves ilegíveis por ACL contam no hive e não no `Get-ChildItem`): aí a divergência
vira sinal de diagnóstico e muda o desenho, não é erro. Raciocínio não é o gargalo — o custo real é
a suíte Pester (~8 s por commit por causa do gate pre-commit).
