# Handoff · Sync Master · 2026-09-03

## Goal
Tornar o Sync Master capaz de **corrigir remotamente** uma árvore WPA patológica (caso real:
laptop i9, 8 anos sem atualizar, **340.000 subchaves**, acessado só por remoto). O procedimento
que funciona roda no WinRE, e é justamente isso que mata o acesso remoto — o trabalho é fechar
esse ciclo sem exigir presença física, ou encaminhar ao máximo.

## State
- HEAD: `89b5ff2` (empurrado; `origin/master` em sincronia)
- Live state: atalho "Sync Master" criado nesta máquina em **duas** pastas reais — Desktop e
  `%APPDATA%\...\Start Menu\Programs` — ambos apontando para `C:\Scripts\Script_Sync\Sync`.
  Se o repo mudar de lugar, rodar a opção 17 de novo. Nenhuma correção WPA foi executada aqui.
- Done nesta sessão: 3 commits. `65eb559` triagem WPA + contagem O(1); `11c03b1` opção 17
  (atalho Desktop + Menu Iniciar); `89b5ff2` opção 18 (guia do reset offline + risco de reativar).
  Gate **269/269**, lint 0 erros / 11 warnings (baseline, composição idêntica ao HEAD anterior).
- In progress: nada mid-flight. O que segue é design aprovado, ainda não escrito.

## Decisions (and why)
- **Não existe "apagador" que rode de dentro do Windows.** A chave é protegida pelo **kernel**,
  não só por ACL — a própria massgrave diz "cannot be deleted normally". `PsExec64 -s` **não**
  resolve; eu afirmei que sim numa resposta anterior e estava errado. Só cede com o hive
  descarregado, fora do Windows. Não reabrir essa ideia.
- **`reagentc /boottore` é o primitivo que remove a presença física** — marca só o próximo boot
  para o WinRE, sem F8/Shift. Mas o WinRE ainda para no menu esperando clique: desatendido exige
  injetar `winpeshl.ini` no `winre.wim`.
- **340k obriga payload idempotente e retomável.** Apagar 340 mil chaves não cabe garantido numa
  janela. Melhor voltar com limpeza parcial e fazer segunda passada do que ficar preso no WinRE.
  Isso troca "timeout longo e arriscado" por "timeout curto + N passadas".
- **BitLocker é gate de abortar, não aviso.** Boot para WinRE com criptografia ligada pode pedir a
  chave de recuperação = brick remoto. Idem bateria de laptop sem AC.
- **Rejeitado: baixar o `rearm.cmd` automaticamente.** Seria uma segunda ponte de execução remota,
  fora da exceção que o `standing.md` abre só para o MAS. Registrado lá.
- **Caminhos paralelos, decidido pelo agente:** *repair install in-place* (`setup.exe /auto upgrade`)
  é a **primeira escolha em máquina remota** — roda de dentro do Windows, reconstrói o hive, é
  suportado, e resolve os 8 anos de updates junto. A automação WinRE é para quando ele não servir.
- **Descartado o argumento "40k não é seu problema"** — era 340k (usuário corrigiu). Na faixa
  patológica a árvore é causa, não cicatriz.

## Next steps (ordered)
1. **`Test-WpaRemoteResetSafety`** — o gate que decide se é seguro tentar remoto: BitLocker/Device
   Encryption em C: (aborta), WinRE presente e habilitado (`reagentc /info`), energia AC em laptop,
   e se a máquina volta sozinha na rede. Tudo exige elevação; sem ela, `Desconhecido`, nunca "ok".
2. **Payload do WinRE**: script de limpeza **idempotente e retomável** + watchdog que reinicia
   incondicionalmente (timeout duro, `wpeutil reboot` sempre, mesmo em falha). É a diferença entre
   ferramenta e tijolo remoto.
3. **Staging no `winre.wim`** (montar, injetar payload + `winpeshl.ini`, desmontar) e disparo com
   `reagentc /boottore` + reboot. Só depois dos gates de 1.
4. **`Invoke-WpaRemoteOfflineReset`** — orquestra: triagem → risco de reativar → safety → captura
   (chave de recuperação + chave de produto + relatório **fora** da máquina, confirmado) → staging
   → disparo → na volta compara hive/contagem e reativa.
5. **Documentar o repair install** como opção remota preferencial (menu ou README), com o passo a
   passo e quando escolher cada caminho.
6. Testes de comportamento para 1 e 4 (mockar coletores, afirmar cada aborto) + navindex + gate.

## Key files
- `modules/Ativacao.psm1` — todo o WPA (38 símbolos; header navindex no topo). Já existem e
  são reusáveis: `Invoke-WpaTriage`, `Get-WpaReactivationRisk`, `Get-WpaHiveSize`,
  `Invoke-WpaOfflineResetGuide`, `Get-WpaSample` (contagem O(1)).
- `modules/Core.psm1` — `New-SyncMasterAtalho` / `Criar-AtalhosSyncMaster` (opção 17).
- `tests/Wpa.Tests.ps1` — comportamento com mocks; padrão `$global:WpaTeste` (nunca `$script:`).
- `tests/Menu.Tests.ps1` — invariantes estáticos; o "nunca remove HKLM\SYSTEM\WPA" segue válido
  e agora tem motivo técnico (kernel), não só política.
- `modules/__navi__.md`, `tests/__navi__.md` — mapas das pastas que os passos tocam.
- `.handoff/standing.md` — decisão sobre reset offline ficar como guia, não automatizado.

## First call
```bash
cd /c/Scripts/Script_Sync/Sync; echo "=== 1 git ==="; git log -3 --oneline; git status --short; echo "=== 2 standing ==="; tail -12 .handoff/standing.md; echo "=== 3 navi modules ==="; sed -n '/Ativacao/,+2p' modules/__navi__.md; echo "=== 4 guia atual ==="; sed -n '/^function Invoke-WpaOfflineResetGuide/,/^}/p' modules/Ativacao.psm1 | head -50; echo "=== 5 risco ==="; sed -n '/^function Get-WpaReactivationRisk/,/^}/p' modules/Ativacao.psm1 | head -40; echo "=== 6 menu 18 ==="; sed -n "/'18' {/,/^                }/p" modules/Ativacao.psm1; echo "=== 7 padrao teste ==="; sed -n '/^Describe .Invoke-WpaOfflineResetGuide/,/^}/p' tests/Wpa.Tests.ps1 | head -30
```

## Open / blockers
- **Não dá para reproduzir o caso aqui.** Esta máquina tem 116 subchaves, é OEM_DM licenciada e
  a sessão **não é elevada** — `reagentc /info` e `Get-BitLockerVolume` deram acesso negado. Todo
  o passo 1 tem de ser validado por mock, e o staging do `winre.wim` (passos 2-3) precisa de uma
  VM descartável antes de chegar perto de máquina de cliente.
- **Respondida (2026-09-03, pelo dono): a máquina remota de 340k NÃO tem BitLocker.** O caminho
  WinRE fica viável nela. O relato é do dono, não medição: `Test-WpaRemoteResetSafety` continua
  conferindo na própria máquina e bloqueando se não conseguir confirmar — Device Encryption em
  Home costuma estar ligado sem o dono saber.
- Sessão em sessão 0 (VS Code tunnel) falha ao instalar MSIX pelo winget (`0x80070520`).

## Skills
- navindex

## Effort
**Alto** para o passo 1. Não é volume de código — é que cada gate que falhar em silêncio vira um
laptop inacessível a quilômetros de distância, e o custo de errar não aparece em teste: aparece
quando alguém precisa pegar a estrada. BitLocker em particular tem várias formas (Device
Encryption, suspensão, protetor TPM-only) e `Get-BitLockerVolume` não é a única fonte de verdade.
Baixa para **médio** nos passos 4-6, que são orquestração e texto sobre peças já prontas.
Raciocínio não é o gargalo nos passos 2-3 — lá o gargalo é ter uma VM para testar de verdade.
