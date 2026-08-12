<div align="center">

# Sync Master

### Ferramentas de sincronização, backup, diagnóstico e manutenção para Windows

**PowerShell 5.1 compatível** · **PowerShell 7 recomendado** · **Windows 10/11**

</div>

> [!IMPORTANT]
> Algumas operações alteram arquivos, serviços, Registro, energia ou discos e podem solicitar elevação pelo UAC. Leia os resumos e confirmações exibidos antes de continuar.

## Visão geral

O Sync Master reúne rotinas administrativas e de engenharia em um menu único. O projeto usa recursos nativos do Windows sempre que possível e separa as funcionalidades em módulos PowerShell testáveis.

| Área | Recursos principais |
|---|---|
| Sincronização | Simulação, cópia unilateral segura, espelhamento, exclusões de perfil e agendamento |
| Backup | Criação e restauração de ZIP, além de clonagem básica de disco |
| Arquivos | Duplicados, hashes, integridade e permissões |
| Sistema | Limpeza, reparo, inicialização, energia, armazenamento e serviços |
| Hardware | CPU, memória, discos, SMART e monitoramento em tempo real |
| Rede | Ping, portas TCP, ARP, DNS, netstat, Whois e teste de velocidade |
| PowerShell | Detecção, instalação e atualização do PowerShell 7 |
| Windows | Diagnóstico de licenciamento, instalação de chave e ativação oficial |

## Início rápido

Escolha uma das duas formas abaixo.

### Opção 1 — clonar com Git

```powershell
git clone https://github.com/Codyte/Sync.git
Set-Location .\Sync
& '.\Sync Master.cmd'
```

Depois, você também pode iniciar o programa clicando duas vezes em **`Sync Master.cmd`**.

### Opção 2 — instalar e executar com IRM

```powershell
irm https://raw.githubusercontent.com/Codyte/Sync/master/install.ps1 | iex
```

Esse comando instala em `%LOCALAPPDATA%\SyncMaster\App` e abre o launcher. Nas próximas execuções, ele consulta o commit atual da `master`: se a instalação já for igual, apenas abre; se houver mudança, atualiza os arquivos sem apagar configurações e logs.

URL equivalente usando o domínio `github.com`:

```powershell
irm https://github.com/Codyte/Sync/raw/refs/heads/master/install.ps1 | iex
```

> [!CAUTION]
> `irm ... | iex` executa imediatamente o conteúdo recebido da internet. Se preferir inspecionar o instalador antes, use a forma em duas etapas:

```powershell
irm https://raw.githubusercontent.com/Codyte/Sync/master/install.ps1 -OutFile $env:TEMP\SyncMaster-install.ps1
& $env:TEMP\SyncMaster-install.ps1
```

Nos dois métodos, o launcher abre o menu como administrador e, quando possível, relança automaticamente no PowerShell 7.

## PowerShell 7

O Windows PowerShell 5.1 já acompanha o Windows e é suficiente para iniciar o bootstrap. O PowerShell 7 é recomendado para o funcionamento completo.

Se ele não estiver instalado, o Sync Master tenta, nesta ordem:

1. WinGet;
2. MSI oficial com assinatura Microsoft validada;
3. instalador oficial da Microsoft;
4. instalação portátil no perfil do usuário quando não há privilégios administrativos.

Também é possível instalar pela [Microsoft Store](https://apps.microsoft.com/detail/9MZ1SNWT0N5D). Depois da instalação, feche e abra novamente o Sync Master.

> [!NOTE]
> A versão da Store é instalada por usuário. Para tarefas agendadas executadas como `SYSTEM`, o Sync Master usa o Windows PowerShell 5.1 quando não encontra uma instalação de sistema do PowerShell 7.

## Modos de uso

### Menu interativo

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Sync_Master.ps1
```

O menu interativo exige privilégios de administrador porque reúne operações que modificam configurações do sistema.

### Sincronização direta

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Sync_Master.ps1 `
  -Acao Sincronizar `
  -Origem 'C:\Dados' `
  -Destino 'D:\Backup' `
  -Modo Unilateral
```

O modo automatizado não abre prompts e pode ser usado pelo Agendador de Tarefas.

> [!WARNING]
> O modo `Bilateral` executa espelhamento nos dois sentidos. Espelhamento e clonagem podem excluir dados no destino. Faça uma simulação ou backup antes de usá-los.

### Instalação como módulo

Para disponibilizar `Start-SyncMaster` em qualquer pasta:

```powershell
.\Install-SyncMaster.ps1
Start-SyncMaster
```

Instalação para todos os usuários, em uma sessão elevada:

```powershell
.\Install-SyncMaster.ps1 -Scope AllUsers
```

Desinstalação:

```powershell
.\Install-SyncMaster.ps1 -Uninstall
```

## Dados e logs

Configurações, backups auxiliares e logs ficam fora do repositório:

```text
%LOCALAPPDATA%\SyncMaster\
├── Logs\
├── Backups\
└── diretorios.json
```

Cada execução interativa tenta criar um transcript em `Logs\sessao_AAAA-MM-DD_HH-mm-ss.log`. Para diagnóstico em outra máquina, envie o transcript mais recente junto com uma captura do erro.

## Segurança

- O MSI baixado pelo bootstrap só é executado quando possui assinatura Authenticode válida da Microsoft.
- Ações destrutivas importantes exigem confirmação no modo interativo.
- O modo de sincronização unilateral não usa `/MIR`.
- Algumas opções destacadas em vermelho baixam conteúdo remoto de terceiros. O endereço, tamanho e SHA-256 são mostrados antes da confirmação; revise a origem antes de autorizar.
- Não execute o projeto a partir de um ZIP sem extrair todos os arquivos.

## Estrutura do projeto

```text
Sync/
├── install.ps1                  # bootstrap para instalação via IRM
├── Sync Master.cmd              # entrada para duplo clique
├── Sync_Master.ps1              # launcher e menu principal
├── SyncMaster.psd1              # manifesto do módulo
├── Install-SyncMaster.ps1       # instalação opcional como módulo
├── modules/                     # funcionalidades por domínio
├── tests/                       # testes Pester
└── tools/                       # lint, testes e hooks locais
```

A análise estática e o gerador de árvore de fluxo possuem [documentação própria](README-FlowTree.md).

## Desenvolvimento e testes

Dependências de desenvolvimento:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

Execute o gate completo:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Run-Checks.ps1
```

O gate executa PSScriptAnalyzer e todos os testes Pester. Para também reprovar warnings de lint:

```powershell
.\tools\Run-Checks.ps1 -FailOnWarning
```

## Solução de problemas

<details>
<summary><strong>PowerShell 7 não foi encontrado</strong></summary>

Confirme se o comando está disponível:

```powershell
Get-Command pwsh -ErrorAction SilentlyContinue
```

Se acabou de instalar pela Store, feche o terminal e execute novamente. Verifique também se o alias de execução `pwsh.exe` está habilitado nas configurações do Windows.

</details>

<details>
<summary><strong>WinGet não foi encontrado</strong></summary>

Atualize ou instale o **App Installer** pela Microsoft Store. O bootstrap ainda tentará os métodos oficiais alternativos.

</details>

<details>
<summary><strong>Falha ao carregar módulos</strong></summary>

Garanta que `Sync_Master.ps1`, `SyncMaster.psd1` e a pasta `modules` permaneçam juntos. Extraia o ZIP inteiro antes de executar.

</details>

<details>
<summary><strong>Preciso enviar um erro</strong></summary>

Inclua a mensagem completa, a versão do Windows e do PowerShell e o arquivo mais recente de:

```text
%LOCALAPPDATA%\SyncMaster\Logs\sessao_*.log
```

</details>

---

<div align="center">

Desenvolvido por **Eng. Carlos Ortiz · Codyte**

</div>
