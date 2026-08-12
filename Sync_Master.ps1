# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L40    PARTE 1: BLOCO DE PARÂMETROS ÚNICO ---
#   L58    New-SyncMasterRelaunchArguments
#   L84    Start-SyncMasterInPowerShell7
#   L110   PARTE 1.1: Relançamento automático em PowerShell 7+ (compatível PS 5)
#   L153   PARTE 2: REGIÃO CENTRALIZADA DE FUNÇÕES ---
#   L228   Menu-Otimizacao
#   L262   Criar-PontoRestauracao
#   L347   Restaurar-PontoRestauracao
#   L482   Menu-LimpezaDisco
#   L510   Configurar-ServicoDefrag
#   L614   Utilitários robustos ===============================================
#   L635   Menu-ReparoSistema
#   L664   Get-PowerPlans
#   L685   Criar-PlanoDeEnergia
#   L701   Menu-CriarPlanoEnergia
#   L722   Menu-OtimizacaoAvancada
#   L809   Menu-Desempenho
#   L874   Menu-GerenciarAgentes
#   L912   Gerenciar-ServicoDeAgente
#   L962   Menu-Ferramentas
#   L988   Menu-Avancado
#   L1030  Gerenciar-EstadosOciososProcessador
#   L1073  Utilitário: enviar arquivo para a Lixeira (PS 5/7) ---
#   L1108  Criar-App
#   L1171  Executor
#   L1245  Aliases de verbo aprovado (retrocompat) ---
#   L1254  PARTE 3: LÓGICA DE EXECUÇÃO PRINCIPAL ---
# ======================= END NAV INDEX =======================

# ===================================================================
# DESCRIÇÃO: Script para sincronização, backup e outras
#            ferramentas de engenharia.
# AUTOR:     Eng. Carlos Ortiz
# VERSÃO:    controlada pelo git (git log / git tag)
# ===================================================================
#Requires -Version 5.1

# --- PARTE 1: BLOCO DE PARÂMETROS ÚNICO ---
# Unificamos todos os parâmetros que o script pode receber aqui.
[CmdletBinding()]
param (
    # Parâmetro interno para o relançamento do PowerShell 7+
    [switch]$IsRelaunched,

    # Parâmetros para execução automatizada (ex: tarefas agendadas)
    [ValidateSet("Menu", "Sincronizar")]
    [string]$Acao = "Menu",

    [string]$Origem = "",
    [string]$Destino = "",
    
    [ValidateSet("Unilateral", "Bilateral")]
    [string]$Modo = "Unilateral"
)

function New-SyncMasterRelaunchArguments {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][System.Collections.IDictionary]$BoundParameters
    )

    $quote = {
        param([AllowEmptyString()][string]$Value)
        "'{0}'" -f $Value.Replace("'", "''")
    }

    $commandParts = @('&', (& $quote $ScriptPath), '-IsRelaunched')
    foreach ($name in 'Acao', 'Origem', 'Destino', 'Modo') {
        if ($BoundParameters.Keys -contains $name) {
            $commandParts += @("-$name", (& $quote ([string]$BoundParameters[$name])))
        }
    }

    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes(($commandParts -join ' '))
    )
    return "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
}

function Start-SyncMasterInPowerShell7 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PwshPath,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][System.Collections.IDictionary]$BoundParameters
    )

    $isAdmin = (
        [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $startSplat = @{
        FilePath         = $PwshPath
        ArgumentList     = New-SyncMasterRelaunchArguments -ScriptPath $ScriptPath -BoundParameters $BoundParameters
        WorkingDirectory = (Get-Location)
        WindowStyle      = 'Normal'
        PassThru         = $true
    }
    if ($isAdmin) { $startSplat['Verb'] = 'RunAs' }

    Start-Process @startSplat
}



# --- PARTE 1.1: Relançamento automático em PowerShell 7+ (compatível PS 5) ---
# Se estamos no Windows PowerShell 5.x e ainda não relançamos, abra o PS7 (pwsh.exe)
# passando os mesmos parâmetros e feche o host atual.
if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $IsRelaunched) {

    # Descobre o pwsh.exe (PS5 não entende ?. então use este padrão)
    $cmdPwsh = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    $pwsh = $null
    if ($cmdPwsh) {
        # Em alguns hosts, o caminho vem em Source; em outros, em Path
        $pwsh = if ($cmdPwsh.Source) { $cmdPwsh.Source } else { $cmdPwsh.Path }
    }
    if (-not $pwsh) {
        # PATH do processo pode estar velho (pwsh instalado nesta mesma sessão) — checa os
        # locais padrão: MSI (ProgramFiles) e zip portátil (LOCALAPPDATA). Inline e não
        # Find-PwshPath (PowerShellUpdate.psm1) porque este bloco roda ANTES dos módulos.
        foreach ($cand in @(
            [IO.Path]::Combine("$env:ProgramFiles", 'PowerShell', '7', 'pwsh.exe'),
            [IO.Path]::Combine("$env:LOCALAPPDATA", 'Microsoft', 'powershell', 'pwsh.exe')
        )) {
            if ($cand -and (Test-Path -LiteralPath $cand)) { $pwsh = $cand; break }
        }
    }

    if (-not $pwsh) {
        Write-Warning "PowerShell 7 (pwsh.exe) não encontrado. Continuando no PS 5.x."
    }
    else {
        try {
            $null = Start-SyncMasterInPowerShell7 `
                -PwshPath $pwsh `
                -ScriptPath $PSCommandPath `
                -BoundParameters $PSBoundParameters
        }
        catch {
            Write-Error ("Falha ao relançar no PowerShell 7: {0}" -f $_.Exception.Message)
        }
        return
    }
}
# ------------------------------------------------------------------------


# --- PARTE 2: REGIÃO CENTRALIZADA DE FUNÇÕES ---

# Modulos extraidos (Fase 5 do refator). Core primeiro (dependencia dos demais),
# depois os outros em ordem alfabetica.
# Caminho deste script de entrada, exposto aos modulos (ex.: Agendar-TarefaSincronizacao
# monta a Tarefa Agendada apontando para CA, nao para o .psm1). $PSCommandPath e' o
# proprio Sync_Master.ps1 mesmo quando chamado de qualquer diretorio.
$env:SYNCMASTER_ENTRY = $PSCommandPath

$modulesDir = Join-Path $PSScriptRoot 'modules'
$manifesto  = Join-Path $PSScriptRoot 'SyncMaster.psd1'
try {
    if (Test-Path $manifesto) {
        # Fase A: ponto de entrada unico e versionado. Carrega Core + dominios e exporta
        # tudo (ver FunctionsToExport no .psd1). Core vem 1o nos NestedModules.
        Import-Module $manifesto -Force -DisableNameChecking -ErrorAction Stop
    } else {
        # Fallback (manifesto ausente): varredura manual, Core primeiro.
        Import-Module (Join-Path $modulesDir 'Core.psm1') -Force -DisableNameChecking -ErrorAction Stop
        Get-ChildItem -Path $modulesDir -Filter '*.psm1' |
            Where-Object Name -ne 'Core.psm1' |
            ForEach-Object { Import-Module $_.FullName -Force -DisableNameChecking -ErrorAction Stop }
    }
} catch {
    Write-Error "Falha ao carregar modulos (manifesto '$manifesto' / pasta '$modulesDir'): $($_.Exception.Message)"
    Read-Host "Pressione Enter para fechar."
    exit 1
}

# LOG DE TUDO: transcript de sessao (grava cronologicamente TODO o console no data dir,
# Logs/sessao_*.log) + footer garantido em qualquer saida (inclusive 'exit') via evento
# de encerramento do engine. Complementa o log diario estruturado (Registrar-Log).
$null = Start-SyncMasterLog
$null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -SupportEvent -Action { Stop-SyncMasterLog }


# Funcoes utilitarias base (Pause-Script, Confirm-Action, Registrar-Log,
# Visualizar-Logs, Ensure-Dir) foram extraidas para modules/Core.psm1.
# Ver Import-Module no topo do script.

#region Funções de Atualização do PowerShell







#endregion

#region Funções de Gerenciamento de Arquivos
# Sync (robocopy + diretorios salvos) extraido para modules\Sync.psm1.








#endregion

#region Funções de Sincronização, Backup e Clonagem






# Código Corrigido:

#endregion


#region Funções de Otimização e Reparo do Sistema
function Menu-Otimizacao {
    do {
        Clear-Host
        Write-Host "--- MENU DE OTIMIZAÇÃO E REPARO DO SISTEMA ---" -ForegroundColor Cyan
        Write-Host "0 - CRIAR PONTO DE RESTAURAÇÃO (Recomendado antes de prosseguir!)" -ForegroundColor Yellow
        Write-Host "00 - RESTAURAR PONTO" -ForegroundColor Green
        Write-Host "1 - Limpeza e Otimização de Disco"
        Write-Host "2 - Verificação e Reparo do Sistema"
        Write-Host "3 - Otimizações de Desempenho"
        Write-Host "4 - Configurações e Reparos de Rede"
        Write-Host "5 - Ferramentas Úteis do Sistema"
        Write-Host "6 - Otimizações AVANÇADAS (Use com extrema cautela!)" -ForegroundColor Red
        Write-Host "7 - Gerenciar Agentes de Monitoramento (MMA/AMA)" -ForegroundColor Magenta
        Write-Host "8 - Gerenciamento de Arquivos (Duplicatas, etc.)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Q - Voltar ao Menu Principal"
        $opcao = Read-Host "Selecione a categoria desejada"
        switch ($opcao.ToUpper()) {
            "0" { Criar-PontoRestauracao }
            "00" { Restaurar-PontoRestauracao }
            "1" { Menu-LimpezaDisco }
            "2" { Menu-ReparoSistema }
            "3" { Menu-Desempenho }
            "4" { Menu-Rede }
            "5" { Menu-Ferramentas }
            "6" { Menu-Avancado }
            "7" { Menu-GerenciarAgentes }
            "8" { Menu-GerenciamentoArquivos }
            "Q" { return }
            default { Write-Warning "Opção inválida."; Pause-Script }
        }
    } while ($opcao.ToUpper() -ne 'Q')
}

function Criar-PontoRestauracao {
<#
.SYNOPSIS
    Cria um Ponto de Restauracao do Sistema (System Restore) no drive C:.
.DESCRIPTION
    Habilita a protecao do sistema se preciso, remove o throttle de frequencia
    temporariamente e cria o ponto via CIM (classe SystemRestore). Restaura a
    configuracao de frequencia ao final. Exige Administrador.
.PARAMETER Descricao
    Texto que identifica o ponto na lista do System Restore.
.PARAMETER Tipo
    Tipo do ponto (APPLICATION_INSTALL/UNINSTALL, DEVICE_DRIVER_INSTALL, MODIFY_SETTINGS).
    Aceita sinonimos, case-insensitive; default MODIFY_SETTINGS.
.EXAMPLE
    Criar-PontoRestauracao -Descricao "Antes de otimizar"
#>
     param(
        [string]$Descricao = "Sync_Master",
        [string]$Tipo = 'MODIFY_SETTINGS'   # aceita sinônimos, case-insensitive
    )

    Write-Host "Iniciando a criação do Ponto de Restauração..." -ForegroundColor Yellow

    # Admin?
    if (-not (Test-IsAdmin)) { throw "Abra o PowerShell como Administrador." }

    $ns  = 'root/default'
    $cls = 'SystemRestore'

    # Normaliza o tipo pedido e mapeia para UInt32
    switch -Regex ($Tipo.ToUpperInvariant()) {
        '^APP(LICATION)?_?INSTALL$'      { $rpType = [uint32]0;  break }
        '^APP(LICATION)?_?UNINSTALL$'    { $rpType = [uint32]1;  break }
        '^DEVICE_?DRIVER_?INSTALL$'      { $rpType = [uint32]10; break }
        '^MOD(IFY)?_?SET(TINGS)?$'       { $rpType = [uint32]12; break }
        default                          { $rpType = [uint32]12 } # seguro
    }
    $eventType = [uint32]100  # Begin System Change

    $freqKey  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqName = 'SystemRestorePointCreationFrequency'
    $prev     = $null

    try {
        # Garante habilitado + sem throttle
        New-Item -Path $freqKey -Force | Out-Null
        Set-ItemProperty $freqKey -Name DisableSR     -Type DWord -Value 0 -Force
        Set-ItemProperty $freqKey -Name DisableConfig -Type DWord -Value 0 -Force
        $prev = (Get-ItemProperty -Path $freqKey -Name $freqName -ErrorAction SilentlyContinue).$freqName
        New-ItemProperty -Path $freqKey -Name $freqName -Value 0 -PropertyType DWord -Force | Out-Null

        # Habilita proteção no C: (alguns sistemas já retornam sucesso sem mudar nada)
        try { Invoke-CimMethod -Namespace $ns -ClassName $cls -MethodName Enable -Arguments @{ Drive='C:\' } | Out-Null } catch { Write-Verbose $_.Exception.Message }

        # Cria o ponto (todos os parâmetros como UInt32 onde precisa)
        $ret = Invoke-CimMethod -Namespace $ns -ClassName $cls -MethodName CreateRestorePoint -Arguments @{
            Description      = $Descricao
            RestorePointType = $rpType
            EventType        = $eventType
        }

        $code = [uint32]$ret.ReturnValue
        if ($code -ne 0) {
            $msgs = @{
                0='OK';1='Acesso negado';2='Não suportado';3='Sem memória';4='Já existe';
                5='Falha WMI';6='Não encontrado';13='Espaço insuficiente';14='Desabilitado';19='System Restore desabilitado'
            }
            throw "Falhou com código $code ($($msgs[$code]))"
        }

        Write-Host "Ponto de Restauração criado com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Warning "Falha ao criar o Ponto de Restauração. Erro: $($_.Exception.Message)"
    }
    finally {
        try {
            if ($null -ne $prev) { Set-ItemProperty -Path $freqKey -Name $freqName -Value $prev | Out-Null }
            else { Remove-ItemProperty -Path $freqKey -Name $freqName -ErrorAction SilentlyContinue }
        } catch { Write-Warning "Não foi possível restaurar '$freqName'. $_" }
    }

    Read-Host "Pressione ENTER para continuar"
}

function Restaurar-PontoRestauracao {
<#
.SYNOPSIS
    Restaura o sistema para um Ponto de Restauração existente (System Restore).

.PARAMETER SequenceNumber
    Número de sequência (SequenceNumber) do ponto a restaurar. Se omitido, abre seleção interativa.

.PARAMETER Filtro
    Texto para filtrar por descrição/data antes da seleção.

.PARAMETER Confirmar
    Pula a confirmação final (uso automático/scriptado).

.PARAMETER Reiniciar
    Reinicia automaticamente ao concluir (shutdown /r /t 0) se a restauração for aceita.

.EXAMPLE
    Restaurar-PontoRestauracao
    # Abre lista interativa de pontos e restaura o escolhido.

.EXAMPLE
    Restaurar-PontoRestauracao -SequenceNumber 127
    # Restaura diretamente o ponto de nº 127.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$SequenceNumber,
        [string]$Filtro,
        [switch]$Confirmar,
        [switch]$Reiniciar
    )

    # 1) Admin checado
    if (-not (Test-IsAdmin)) {
        throw "Abra o PowerShell como Administrador para restaurar um ponto."
    }

    # 2) Carrega pontos
    $ns  = 'root/default'
    $cls = 'SystemRestore'
    try {
        $points = Get-CimInstance -Namespace $ns -ClassName $cls |
                  Sort-Object CreationTime -Descending |
                  Select-Object @{
                        Name='DataHora'; Expression={ [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) }
                  }, Description, SequenceNumber
    } catch {
        throw "Não foi possível listar pontos de restauração: $($_.Exception.Message)"
    }

    if (-not $points) { throw "Nenhum ponto de restauração encontrado." }

    # 3) Seleção
    $target = $null
    if ($PSBoundParameters.ContainsKey('SequenceNumber')) {
        $target = $points | Where-Object { $_.SequenceNumber -eq $SequenceNumber }
        if (-not $target) { throw "SequenceNumber $SequenceNumber não encontrado." }
    } else {
        $lista = $points
        if ($Filtro) {
            $lista = $lista | Where-Object {
                $_.Description -like "*$Filtro*" -or
                ($_.DataHora.ToString('yyyy-MM-dd HH:mm') -like "*$Filtro*")
            }
            if (-not $lista) { throw "Nenhum ponto corresponde ao filtro '$Filtro'." }
        }

        # Preferir Out-GridView se existir (só no Windows PowerShell ou PS7 com modulo adequado)
        if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
            $target = $lista | Out-GridView -Title "Selecione o ponto de restauração" -PassThru
            if (-not $target) { Write-Warning "Operação cancelada."; return }
        } else {
            # Seleção via console
            Write-Host "`nPontos disponíveis:" -ForegroundColor Yellow
            $i = 0
            $menu = $lista | ForEach-Object {
                $i++; [PSCustomObject]@{Idx=$i; Data=$_.DataHora; Descricao=$_.Description; Seq=$_.SequenceNumber}
            }
            $menu | Format-Table -AutoSize
            $escolha = Read-Host "Digite o índice (Idx) a restaurar"
            if (-not ($escolha -as [int])) { throw "Índice inválido." }
            $target = $menu | Where-Object { $_.Idx -eq [int]$escolha } |
                      ForEach-Object { $points | Where-Object SequenceNumber -eq $_.Seq }
            if (-not $target) { throw "Índice $escolha não encontrado." }
        }
    }

    $msg = "Restaurar para [$($target.DataHora.ToString('yyyy-MM-dd HH:mm'))] - '$($target.Description)' (Seq $($target.SequenceNumber))"
    if (-not $Confirmar) {
        $go = Read-Host "$msg ? (S/N)"
        if ($go.ToUpperInvariant() -ne 'S') { Write-Warning "Operação cancelada."; return }
    }

    # 4) Executa restauração
    Write-Host "Solicitando restauração do sistema..." -ForegroundColor Yellow
    Registrar-Log ("Restaurar-PontoRestauracao: Seq {0} - '{1}'" -f $target.SequenceNumber, $target.Description)
    $ret = Invoke-CimMethod -Namespace $ns -ClassName $cls -MethodName Restore -Arguments @{
        RestorePoint = [uint32]$target.SequenceNumber
    }

    $code = [uint32]$ret.ReturnValue
    $msgs = @{
        0='OK (solicitado). O sistema precisa reiniciar.'
        1='Acesso negado'
        2='Não suportado'
        3='Sem memória'
        4='Já existe'
        5='Falha WMI'
        6='Não encontrado'
        13='Espaço insuficiente'
        14='Desabilitado'
        19='System Restore desabilitado'
    }

    if ($code -ne 0) {
        throw "Falhou com código $code ($($msgs[$code]))"
    }

    Write-Host $msgs[$code] -ForegroundColor Green
    if ($Reiniciar) {
        Write-Host "Reiniciando agora..." -ForegroundColor Yellow
        shutdown.exe /r /t 0
    } else {
        Write-Host "Reinicie o computador para concluir a restauração." -ForegroundColor Yellow
    }
}

# Alias sem acento (opcional)
Set-Alias -Name Restaurar-PontoDeRestauracao -Value Restaurar-PontoRestauracao -Force




#region SubMenu: Limpeza de Disco
function Menu-LimpezaDisco {
    do {
        Clear-Host; Write-Host "--- LIMPEZA E OTIMIZAÇÃO DE DISCO ---" -ForegroundColor Cyan
        Write-Host "1. Abrir Limpeza de Disco do Windows"
        Write-Host "2. Otimizar Unidades (Desfragmentar/TRIM)"
        Write-Host "3. Desativar Hibernação (Libera espaço)"
        Write-Host "4. Reativar Hibernação"
        Write-Host "5. Verificar e Ativar TRIM para SSDs"
        Write-Host "6. Configurar Serviço de Otimização de Unidades (Defrag)"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' { Write-Host "Iniciando Limpeza de Disco..."; Start-Process "cleanmgr.exe" -Wait; Pause-Script }
            '2' { Write-Host "Iniciando Otimizador de Unidades..."; Start-Process "dfrgui.exe"; Pause-Script }
            '3' { if(Confirm-Action "Desativar a hibernação?"){ powercfg -h off; Registrar-Log "Hibernacao DESATIVADA (powercfg -h off)" }; Pause-Script }
            '4' { if(Confirm-Action "Reativar a hibernação?"){ powercfg -h on; Registrar-Log "Hibernacao REATIVADA (powercfg -h on)" }; Pause-Script }
            '5' {
                fsutil behavior query DisableDeleteNotify
                if(Confirm-Action "Garantir que o TRIM esteja ATIVADO (valor 0)?"){ fsutil behavior set DisableDeleteNotify 0; Registrar-Log "TRIM ativado (DisableDeleteNotify=0)" }
                Pause-Script
            }
            '6' { Configurar-ServicoDefrag }
            'Q' { return }
            default {Write-Warning "Opção inválida."}
        }
    } while($true)
}

function Configurar-ServicoDefrag {
    Clear-Host; Write-Host "--- CONFIGURAÇÃO DO SERVIÇO DE OTIMIZAÇÃO DE UNIDADES (defragsvc) ---" -ForegroundColor Cyan
    try {
        $servico = Get-Service defragsvc -ErrorAction Stop
        Write-Host "Status atual do serviço '$($servico.DisplayName)':"
        Write-Host " Nome       : $($servico.Name)"
        Write-Host " Status     : $($servico.Status)"
        Write-Host " Tipo Inicial: $($servico.StartupType)"
        Write-Host "-----------------------------------------------------"
    } catch {
        Write-Warning "Não foi possível obter informações do serviço 'defragsvc'. $($_.Exception.Message)"
        Pause-Script
        return
    }

    Write-Host "Opções:"
    Write-Host "1. Definir Inicialização como AUTOMÁTICA e INICIAR serviço"
    Write-Host "2. Definir Inicialização como MANUAL"
    Write-Host "3. PARAR serviço (se estiver em execução)"
    Write-Host "4. INICIAR serviço (se estiver parado e não desabilitado)"
    Write-Host "Q. Voltar"
    $escolha = Read-Host "Sua escolha"

    try {
        switch ($escolha.ToUpper()) {
            '1' {
                if(Confirm-Action "Definir 'defragsvc' como Automático e Iniciar?") {
                    Set-Service defragsvc -StartupType Automatic
                    Start-Service defragsvc
                    Registrar-Log "defragsvc -> Automatico + iniciado"
                    Write-Host "Serviço 'defragsvc' configurado como Automático e iniciado." -ForegroundColor Green
                }
            }
            '2' {
                if(Confirm-Action "Definir 'defragsvc' como Manual?") {
                    Set-Service defragsvc -StartupType Manual
                    Registrar-Log "defragsvc -> Manual"
                    Write-Host "Serviço 'defragsvc' configurado como Manual." -ForegroundColor Green
                }
            }
            '3' {
                if ($servico.Status -eq "Running") {
                    if(Confirm-Action "Parar o serviço 'defragsvc'?") {
                        Stop-Service defragsvc -Force
                        Registrar-Log "defragsvc -> parado"
                        Write-Host "Serviço 'defragsvc' parado." -ForegroundColor Green
                    }
                } else { Write-Warning "Serviço 'defragsvc' não está em execução."}
            }
            '4' {
                 if ($servico.Status -ne "Running" -and $servico.StartupType -ne "Disabled") {
                    if(Confirm-Action "Iniciar o serviço 'defragsvc'?") {
                        Start-Service defragsvc
                        Registrar-Log "defragsvc -> iniciado"
                        Write-Host "Serviço 'defragsvc' iniciado." -ForegroundColor Green
                    }
                } elseif ($servico.StartupType -eq "Disabled") {
                    Write-Warning "Serviço 'defragsvc' está desabilitado. Altere o tipo de inicialização primeiro."
                } else { Write-Warning "Serviço 'defragsvc' já está em execução."}
            }
            'Q' { return }
            default { Write-Warning "Opção inválida."}
        }
    } catch {
        Write-Warning "Ocorreu um erro ao gerenciar o serviço: $($_.Exception.Message)"
    }
    Pause-Script
}
#endregion
#region SubMenu: Diagnóstico de Rede Avançado




















#endregion

#region Funções de Ativação, Diagnóstico e Permissões











# === Utilitários robustos ===============================================


















#endregion
#region SubMenu: Reparo do Sistema
function Menu-ReparoSistema {
    do {
        Clear-Host; Write-Host "--- VERIFICAÇÃO E REPARO DO SISTEMA ---" -ForegroundColor Cyan
        Write-Host "1. Verificar Integridade dos Arquivos (SFC)"
        Write-Host "2. Verificar Imagem do Sistema (DISM CheckHealth)"
        Write-Host "3. Restaurar Imagem do Sistema (DISM RestoreHealth)"
        Write-Host "4. Verificar Disco por Erros (CHKDSK)"
        Write-Host "5. Ferramenta de Remoção de Software Mal-Intencionado (MRT)"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' { Write-Host "Iniciando SFC..."; Start-Process "sfc" -ArgumentList "/scannow" -Wait -Verb RunAs; Pause-Script }
            '2' { Write-Host "Iniciando DISM CheckHealth..."; Start-Process "dism" -ArgumentList "/online /cleanup-image /CheckHealth" -Wait -Verb RunAs; Pause-Script }
            '3' { Write-Host "Iniciando DISM RestoreHealth..."; Start-Process "dism" -ArgumentList "/online /cleanup-image /RestoreHealth" -Wait -Verb RunAs; Pause-Script }
            '4' { 
                $drive = Read-Host "Qual letra de unidade deseja verificar (ex: C)?"
                if(Confirm-Action "Executar CHKDSK em $drive:? (pode exigir reinicialização)"){ chkdsk "$($drive):" /f /r /b }
                Pause-Script
            }
            '5' { Write-Host "Iniciando MRT..."; Start-Process "mrt.exe" -Wait; Pause-Script }
            'Q' { return }
            default {Write-Warning "Opção inválida."}
        }
    } while($true)
}
#endregion

#region SubMenu: Desempenho
# Esta função foi reescrita para ser independente do idioma do Windows, usando GUIDs.
function Get-PowerPlans {
    $guidRegex = '[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}'
    $planos = @()
    powercfg /list | ForEach-Object {
        if ($_ -match $guidRegex) {
            $guidEncontrado = $matches[0]
            $nomePlano = ''
            if ($_ -match '\((.+?)\)') {
                $nomePlano = $matches[1]
            }
            $planoEstaAtivo = $_.Trim().EndsWith('*')
            $planos += [PSCustomObject]@{
                GUID     = $guidEncontrado
                Name     = $nomePlano
                IsActive = $planoEstaAtivo
            }
        }
    }
    return $planos
}

function Criar-PlanoDeEnergia {
    param(
        [Parameter(Mandatory=$true)] [string]$NomeDoPlano,
        [Parameter(Mandatory=$true)] [string]$GuidDoPlano
    )
    Write-Host "Tentando criar/restaurar o plano de energia: $NomeDoPlano..." -ForegroundColor Yellow
    try {
        powercfg -duplicatescheme $GuidDoPlano | Out-Null
        Write-Host "Plano '$NomeDoPlano' criado ou restaurado com sucesso!" -ForegroundColor Green
        Registrar-Log "Plano de energia '$NomeDoPlano' foi criado/restaurado."
    } catch {
        Write-Warning "Não foi possível criar o plano '$NomeDoPlano'."
    }
    Pause-Script
}

function Menu-CriarPlanoEnergia {
    do {
        Clear-Host
        Write-Host "--- CRIAÇÃO DE PLANOS DE ENERGIA ---" -ForegroundColor Cyan
        Write-Host "1. Economia de Energia"
        Write-Host "2. Equilibrado (Padrão)"
        Write-Host "3. Alto Desempenho"
        Write-Host "4. Desempenho Máximo"
        Write-Host "Q. Voltar"
        $escolha = Read-Host "Sua escolha"
        switch ($escolha.ToUpper()) {
            '1' { Criar-PlanoDeEnergia -NomeDoPlano "Economia de Energia" -GuidDoPlano "a1841308-3541-4fab-bc81-f71556f20b4a" }
            '2' { Criar-PlanoDeEnergia -NomeDoPlano "Equilibrado" -GuidDoPlano "381b4222-f694-41f0-9685-ff5bb260df2e" }
            '3' { Criar-PlanoDeEnergia -NomeDoPlano "Alto Desempenho" -GuidDoPlano "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" }
            '4' { Criar-PlanoDeEnergia -NomeDoPlano "Desempenho Máximo" -GuidDoPlano "e9a42b02-d5df-448d-aa00-03f14749eb61" }
            'Q' { return }
            default { Write-Warning "Opção inválida."; Pause-Script }
        }
    } while ($true)
}

function Menu-OtimizacaoAvancada {

    # ========================= MENU PRINCIPAL ============================
    do {
        Clear-Host
        Write-Host "=== OTIMIZAÇÃO E DESEMPENHO AVANÇADO ===" -ForegroundColor Cyan
        Write-Host " 0. Backup automático do Registro (recomendado)"
        Write-Host " 1. DisablePagingExecutive  (baixo impacto; cuidado)"
        Write-Host " 2. LargeSystemCache        (APENAS servidor)"
        Write-Host " 3. Desabilitar Hibernação  (libera espaço)"
        Write-Host " 4. Plano de energia recomendado (Desktop/Notebook)"
        Write-Host " 5. Desabilitar Telemetria (GP Policy) [efeito pequeno]"
        Write-Host " 6. MenuShowDelay (UI mais ágil)"
        Write-Host " 7. Limpeza de temporários + Component Store (DISM)"
        Write-Host " 8. Voltar ao menu anterior"
        Write-Host " 9. Restaurar valores padrão/recomendados"
        Write-Host "10. Mostrar estado atual das otimizações"
        Write-Host "11. Startups (habilitar/desabilitar)"
        Write-Host "12. Manutenção de armazenamento (TRIM/Defrag)"
        Write-Host "13. SMART do disco (básico)"
        Write-Host "14. Energia/CPU afinado"
        Write-Host "15. Indexador: pausar/retomar"
        Write-Host "16. Tarefas agendadas ruidosas"
        $opcao = Read-Host "`nEscolha uma opção"
        switch ($opcao) {
            '0' { Backup-Registro; Pause-Local }
            '1' {
                Require-Admin
                Set-DWord "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1
                Write-Host "Núcleo/serviços mantidos em RAM. Monitore o uso de memória." -ForegroundColor Yellow
                Pause-Local
            }
            '2' {
                Require-Admin
                if (Is-ServerOS) {
                    Set-DWord "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 1
                    Write-Host "LargeSystemCache ativado (server)." -ForegroundColor Green
                } else {
                    Write-Warning "LargeSystemCache é para SERVIDOR. Não aplicado em cliente."
                }
                Pause-Local
            }
            '3' {
                Require-Admin
                powercfg /h off | Out-Null
                Set-DWord "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" 0
                Write-Host "Hibernação desativada (espaço liberado)." -ForegroundColor Green
                Pause-Local
            }
            '4' { Toggle-PowerPlan; Pause-Local }
            '5' {
                Require-Admin
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
                Set-DWord "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
                Write-Host "Política aplicada (pode exigir Pro/Enterprise para efeito pleno)." -ForegroundColor Yellow
                Pause-Local
            }
            '6' {
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "100"
                Write-Host "Menus mais responsivos (efeito visual)." -ForegroundColor Green
                Pause-Local
            }
            '7' { Clean-Temp; Pause-Local }
            '8' { break }
            '9' {
                Require-Admin
                Set-DWord "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 0
                Set-DWord "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0
                Set-DWord "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" 1
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "400"
                Write-Host "Valores restaurados ao padrão recomendável." -ForegroundColor Yellow
                Pause-Local
            }
            '10' { Show-Estado; Pause-Local }
            '11' { Menu-Startups }
            '12' { Storage-Maintenance }
            '13' { Disk-SMART }
            '14' { Power-CPU-Tune }
            '15' { SearchIndexer-Toggle }
            '16' { Tasks-Noise }
            default { Write-Host "Opção inválida, tente novamente." -ForegroundColor Red; Pause-Local }
        }
    } while ($opcao -ne '8')
}



function Menu-Desempenho {
    do {
        Clear-Host
        Write-Host "--- OTIMIZAÇÕES DE DESEMPENHO ---" -ForegroundColor Cyan
        Write-Host "1. Gerenciar Programas de Inicialização"
        Write-Host "2. Ajustar Efeitos Visuais para Melhor Desempenho"
        Write-Host "3. Criar Plano de Energia"
        Write-Host "4. Selecionar Plano de Energia"
        Write-Host "5. Excluir Plano de Energia"
        Write-Host "6. Configurações de Elementos Gráficos (Apps/Jogos)"
        Write-Host "7. Otimização Avançada de Registro"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' { Start-Process "taskmgr.exe" -ArgumentList "/0/startup"; Pause-Script }
            '2' { Start-Process "SystemPropertiesPerformance.exe"; Pause-Script }
            '3' { Menu-CriarPlanoEnergia }
            '4' { 
                $planos = Get-PowerPlans
                if ($planos.Count -eq 0) { Write-Warning "Nenhum plano de energia encontrado."; } else {
                    Write-Host "`nPlanos de Energia Disponíveis:" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $planos.Count; $i++) {
                        $status = if ($planos[$i].IsActive) { "(Ativo)" } else { "" }
                        Write-Host ("{0}. {1} {2}" -f ($i + 1), $planos[$i].Name, $status)
                    }
                    $escolha = Read-Host "`nDigite o NÚMERO do plano para ATIVAR"
                    if ($escolha -match '^\d+$' -and [int]$escolha -ge 1 -and [int]$escolha -le $planos.Count) {
                        $planoSelecionado = $planos[[int]$escolha - 1]
                        powercfg /setactive $planoSelecionado.GUID
                        Write-Host "Plano '$($planoSelecionado.Name)' ativado." -ForegroundColor Green
                    } else { Write-Warning "Seleção inválida." }
                }
                Pause-Script
            }
            '5' { 
                $planos = Get-PowerPlans
                if ($planos.Count -eq 0) { Write-Warning "Nenhum plano de energia encontrado."; } else {
                    Write-Host "`nPlanos Disponíveis para Exclusão:" -ForegroundColor Yellow
                     for ($i = 0; $i -lt $planos.Count; $i++) {
                        $status = if ($planos[$i].IsActive) { "(Ativo - Não pode ser excluído)" } else { "" }
                        Write-Host ("{0}. {1} {2}" -f ($i + 1), $planos[$i].Name, $status) -ForegroundColor $(if($planos[$i].IsActive){'Gray'}else{'White'})
                    }
                    $escolha = Read-Host "`nDigite o NÚMERO do plano para EXCLUIR"
                     if ($escolha -match '^\d+$' -and [int]$escolha -ge 1 -and [int]$escolha -le $planos.Count) {
                        $planoSelecionado = $planos[[int]$escolha - 1]
                        if ($planoSelecionado.IsActive) { Write-Warning "Não é possível excluir o plano ativo." } else {
                            if (Confirm-Action "Excluir o plano '$($planoSelecionado.Name)'?") {
                                powercfg /delete $planoSelecionado.GUID
                                Write-Host "Plano '$($planoSelecionado.Name)' removido." -ForegroundColor Green
                            }
                        }
                    } else { Write-Warning "Seleção inválida." }
                }
                Pause-Script
            }
            '6' { Start-Process "ms-settings:display-advancedgraphics"; Pause-Script }
            '7' { Menu-OtimizacaoAvancada }
            'Q' { return }
            default { Write-Warning "Opção inválida."; Pause-Script }
        }
    } while($true)
}
#endregion

#region SubMenu: Agentes de Monitoramento
function Menu-GerenciarAgentes {
    do {
        Clear-Host; Write-Host "--- GERENCIAR AGENTES DE MONITORAMENTO ---" -ForegroundColor Cyan
        Write-Warning "Parar estes serviços impedirá o envio de dados para o Azure Monitor/SCOM."
        Write-Host ""
        Write-Host "--- MMA (Agente Legado - HealthService) ---"
        Write-Host "1. Verificar Status do MMA"
        Write-Host "2. Parar MMA"
        Write-Host "3. Iniciar MMA"
        Write-Host "4. Desabilitar MMA (Inicialização desativada)"
        Write-Host "5. Habilitar MMA (Inicialização automática)"
        Write-Host "--- AMA (Novo Agente - AzureMonitorAgent) ---"
        Write-Host "6. Verificar Status do AMA"
        Write-Host "7. Parar AMA"
        Write-Host "8. Iniciar AMA"
        Write-Host "9. Desabilitar AMA"
        Write-Host "10. Habilitar AMA"
        Write-Host "Q. Voltar"

        $escolhaAgente = Read-Host "Sua escolha"
        switch($escolhaAgente.ToUpper()) {
            '1' { Gerenciar-ServicoDeAgente -NomeDoServico "HealthService" -Acao "Status" }
            '2' { Gerenciar-ServicoDeAgente -NomeDoServico "HealthService" -Acao "Parar" }
            '3' { Gerenciar-ServicoDeAgente -NomeDoServico "HealthService" -Acao "Iniciar" }
            '4' { Gerenciar-ServicoDeAgente -NomeDoServico "HealthService" -Acao "Desabilitar" }
            '5' { Gerenciar-ServicoDeAgente -NomeDoServico "HealthService" -Acao "Habilitar" }
            '6' { Gerenciar-ServicoDeAgente -NomeDoServico "AzureMonitorAgent" -Acao "Status" }
            '7' { Gerenciar-ServicoDeAgente -NomeDoServico "AzureMonitorAgent" -Acao "Parar" }
            '8' { Gerenciar-ServicoDeAgente -NomeDoServico "AzureMonitorAgent" -Acao "Iniciar" }
            '9' { Gerenciar-ServicoDeAgente -NomeDoServico "AzureMonitorAgent" -Acao "Desabilitar" }
            '10' { Gerenciar-ServicoDeAgente -NomeDoServico "AzureMonitorAgent" -Acao "Habilitar" }
            'Q' { return }
            default { Write-Warning "Opção inválida." }
        }
        Pause-Script
    } while ($true)
}

function Gerenciar-ServicoDeAgente {
    param(
        [string]$NomeDoServico,
        [string]$Acao
    )
    try {
        $servico = Get-Service $NomeDoServico -ErrorAction Stop
    } catch {
        Write-Warning "O serviço '$NomeDoServico' não foi encontrado nesta máquina."
        return
    }

    switch($Acao) {
        "Status" {
            Write-Host "Status do serviço '$($servico.DisplayName)' ($NomeDoServico):"
            $servico | Select-Object Name, DisplayName, Status, StartupType
        }
        "Parar" {
            if ($servico.Status -eq "Running") {
                if (Confirm-Action "Parar o serviço '$NomeDoServico'?") { Stop-Service -Name $NomeDoServico -Force; Registrar-Log "Agente '$NomeDoServico' -> parado"; Write-Host "'$NomeDoServico' parado." -ForegroundColor Green }
            } else { Write-Warning "'$NomeDoServico' já está parado." }
        }
        "Iniciar" {
            if ($servico.Status -ne "Running") {
                if (Confirm-Action "Iniciar o serviço '$NomeDoServico'?") { Start-Service -Name $NomeDoServico; Registrar-Log "Agente '$NomeDoServico' -> iniciado"; Write-Host "'$NomeDoServico' iniciado." -ForegroundColor Green }
            } else { Write-Warning "'$NomeDoServico' já está em execução." }
        }
        "Desabilitar" {
            if ($servico.StartupType -ne "Disabled") {
                if (Confirm-Action "DESABILITAR o serviço '$NomeDoServico'?") { Set-Service -Name $NomeDoServico -StartupType Disabled; Registrar-Log "Agente '$NomeDoServico' -> desabilitado (Startup=Disabled)"; Write-Host "'$NomeDoServico' desabilitado." -ForegroundColor Green }
            } else { Write-Warning "'$NomeDoServico' já está desabilitado." }
        }
        "Habilitar" {
             if ($servico.StartupType -ne "Automatic") {
                if (Confirm-Action "HABILITAR (Automático) o serviço '$NomeDoServico'?") { Set-Service -Name $NomeDoServico -StartupType Automatic; Registrar-Log "Agente '$NomeDoServico' -> habilitado (Startup=Automatic)"; Write-Host "'$NomeDoServico' habilitado." -ForegroundColor Green }
            } else { Write-Warning "'$NomeDoServico' já está habilitado." }
        }
    }
}
#endregion

#region SubMenu: Rede





#endregion

#region SubMenu: Ferramentas do Sistema
function Menu-Ferramentas {
    do {
        Clear-Host; Write-Host "--- ATALHOS PARA FERRAMENTAS DO SISTEMA ---" -ForegroundColor Cyan
        Write-Host "1. Propriedades do Sistema (sysdm.cpl)"
        Write-Host "2. Programas e Recursos (appwiz.cpl)"
        Write-Host "3. Gerenciador de Dispositivos (devmgmt.msc)"
        Write-Host "4. Serviços (services.msc)"
        Write-Host "5. Configuração do Sistema (msconfig)"
        Write-Host "6. Monitor de Recursos (resmon)"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' { Start-Process "sysdm.cpl" }
            '2' { Start-Process "appwiz.cpl" }
            '3' { Start-Process "devmgmt.msc" }
            '4' { Start-Process "services.msc" }
            '5' { Start-Process "msconfig.exe" }
            '6' { Start-Process "resmon.exe" }
            'Q' { return }
            default {Write-Warning "Opção inválida."}
        }
    } while($true)
}
#endregion

#region SubMenu: Avançado (COM AVISOS)
function Menu-Avancado {
     do {
        Clear-Host
        Write-Host "--- OTIMIZAÇÕES AVANÇADAS ---" -ForegroundColor Red
        Write-Warning "AVISO: Alterações aqui podem afetar a estabilidade do sistema."
        Write-Warning "Prossiga apenas se souber o que está fazendo."
        Write-Host "1. Ajustar Cache do Sistema de Arquivos (Fsutil memoryusage)"
        Write-Host "2. Gerenciar Estados Ociosos do Processador"
        Write-Host "3. Ajustes de Timer do Sistema (BCDEDIT - MUITO PERIGOSO)"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' {
                fsutil behavior query memoryusage
                $val = Read-Host "Definir para 2 (Otimizado para Cache) ou 1 (Padrão)?"
                if($val -in '1','2'){
                    if(Confirm-Action "Tem certeza?"){ fsutil behavior set memoryusage $val }
                }
                Pause-Script
            }
            '2' { Gerenciar-EstadosOciososProcessador }
            '3' {
                Write-Warning "Alterar BCDEDIT pode impedir o boot do sistema. NÃO prossiga sem um backup completo."
                if(Confirm-Action -Prompt "Entendo os riscos e desejo prosseguir?"){
                    if (Confirm-Action -Prompt "Criar um Ponto de Restauração antes? (fortemente recomendado)") {
                        Criar-PontoRestauracao -Descricao "Antes de bcdedit (Sync Master)"
                    }
                    $bcd_cmd = Read-Host "Digite o comando bcdedit COMPLETO a ser executado (ex: /set useplatformclock true)"
                    if ([string]::IsNullOrWhiteSpace($bcd_cmd)) { Write-Warning "Nenhum comando inserido." }
                    elseif(Confirm-Action -Prompt "Executar 'bcdedit $bcd_cmd'?"){
                        Registrar-Log "bcdedit $bcd_cmd (executado pelo usuario)"
                        Start-Process "bcdedit" -ArgumentList $bcd_cmd -Wait -Verb RunAs
                    }
                }
                Pause-Script
            }
            'Q' { return }
            default {Write-Warning "Opção inválida."}
        }
    } while($true)
}

function Gerenciar-EstadosOciososProcessador { 
    Clear-Host; Write-Host "--- GERENCIAR ESTADOS OCIOSOS DO PROCESSADOR ---" -ForegroundColor Red
    Write-Warning "Desabilitar pode aumentar desempenho em casos raros, mas AUMENTARÁ consumo de energia e calor."
    Write-Host "1. HABILITAR Estados Ociosos (Padrão Recomendado)"
    Write-Host "2. DESABILITAR Estados Ociosos (Risco)"
    Write-Host "Q. Voltar"
    $escolhaOcioso = Read-Host "Sua escolha"

    switch ($escolhaOcioso.ToUpper()) {
        '1' {
            if (Confirm-Action "HABILITAR estados ociosos (IDLEDISABLE = 0)?") {
                Powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 0
                Powercfg /SETACTIVE SCHEME_CURRENT
                Registrar-Log "Estados ociosos do processador HABILITADOS (IDLEDISABLE=0)"
                Write-Host "Estados ociosos HABILITADOS." -ForegroundColor Green
            }
        }
        '2' {
            if (Confirm-Action -Prompt "AVISO: Desabilitar estados ociosos (IDLEDISABLE = 1)?") {
                 if (Confirm-Action -Prompt "Criar um Ponto de Restauração antes? (recomendado)") {
                    Criar-PontoRestauracao -Descricao "Antes de desabilitar idle states (Sync Master)"
                 }
                 if (Confirm-Action -Prompt "CONFIRMAÇÃO FINAL: Continuar?") {
                    Powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 1
                    Powercfg /SETACTIVE SCHEME_CURRENT
                    Registrar-Log "Estados ociosos do processador DESABILITADOS (IDLEDISABLE=1) - RISCO termico"
                    Write-Host "Estados ociosos DESABILITADOS." -ForegroundColor Red
                 }
            }
        }
        'Q' { return }
        default { Write-Warning "Opção inválida." }
    }
    Pause-Script
}
#endregion





#region SubMenu: Gerenciamento de Arquivos (corrigido e balanceado)

# --- Utilitário: enviar arquivo para a Lixeira (PS 5/7) ---
try {
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop | Out-Null
} catch {  Write-Verbose $_.Exception.Message }


# Confirm-Action e fornecida por modules/Core.psm1 (importado no topo). O fallback
# local antigo foi removido por ser codigo morto.





#endregion



#region Funções de Sistema e Diagnóstico















#endregion

function Criar-App {
    param (
        [string]$IconFile
    )

    # Configuração
    $caminhoDoExecutavel = "C:\Program Files (x86)\WindowsPowerShell\Modules\ps2exe.1.0.13\Win-PS2EXE.exe"

    # Verifica se o executável existe
    if (-not (Test-Path $caminhoDoExecutavel)) {
        Write-Error "❌ Win-PS2EXE.exe não encontrado em '$caminhoDoExecutavel'."
        Write-Error "Atualize o caminho na variável `$caminhoDoExecutavel`."
        Pause-Script
        return
    }

    # Arquivo de origem (o próprio script) e saída.
    # $MyInvocation.MyCommand.Path e' NULO dentro de uma funcao (reflete a invocacao da
    # funcao, nao do script) -> ChangeExtension($null) lanca e -inputFile fica vazio.
    # $PSCommandPath e' o caminho do .ps1 em execucao; fallback p/ a entry exposta no topo.
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $env:SYNCMASTER_ENTRY }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        Write-Error "Não foi possível resolver o caminho do script para compilar."
        Pause-Script
        return
    }
    $outputFile = [System.IO.Path]::ChangeExtension($scriptPath, ".exe")

    Write-Host "`n--- COMPILANDO SCRIPT ---" -ForegroundColor Cyan
    Write-Host "Executável: $caminhoDoExecutavel"
    Write-Host "Origem:     $scriptPath"
    Write-Host "Saída:      $outputFile"

    # Argumentos
    $argumentos = @(
        "-inputFile", $scriptPath,
        "-outputFile", $outputFile
    )

    # Ícone (opcional)
    if ($IconFile -and (Test-Path $IconFile)) {
        $argumentos += "-iconFile", $IconFile
        Write-Host "Ícone aplicado: $IconFile"
    }

    # Execução do PS2EXE
    try {
        & $caminhoDoExecutavel @argumentos
        Write-Host "✔️ SUCESSO: EXE criado em '$outputFile'!" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ FALHA ao executar o conversor."
        Write-Error $_.Exception.Message
    }

    Pause-Script
}



#region Funções da GUI (MicroWin / Coop / WinUtil)
# TODAS as funções e a lógica do bloco "Coop" e "Executor" estão contidas aqui.
# A função 'Executor' serve como o ponto de entrada para toda a interface gráfica.
function Executor {
<#
.SYNOPSIS
    Baixa e executa o WinUtil (Chris Titus Tech) com verificacao de integridade.
.DESCRIPTION
    Em vez de baixar-e-executar as cegas, baixa o script para uma string, calcula e
    exibe o SHA256, e (se informado) compara com um hash esperado, abortando se nao bater.
.PARAMETER Url
    URL do WinUtil. Default https://christitus.com/win.
.PARAMETER ExpectedSha256
    Hash SHA256 esperado (pin opcional). Tambem pode vir de env WINUTIL_EXPECTED_SHA256.
    Se fornecido e nao corresponder, a execucao e abortada.
.EXAMPLE
    Executor -ExpectedSha256 'abc123...'   # so executa se o conteudo casar com o hash
#>
    # WinUtil (Chris Titus Tech) e carregado remoto via irm. Antes era um embed
    # de ~16k linhas (v25.06.27); ver historico git para aquela versao pinada.
    #
    # ENDURECIMENTO (supply-chain): em vez de baixar-e-executar as cegas, o
    # script agora (1) baixa o conteudo para uma string, (2) calcula o SHA256 e
    # mostra antes de rodar, (3) se um hash esperado for fornecido (parametro
    # -ExpectedSha256 ou env WINUTIL_EXPECTED_SHA256), ABORTA quando nao bate.
    param(
        [string]$Url = 'https://christitus.com/win',
        [string]$ExpectedSha256 = $env:WINUTIL_EXPECTED_SHA256
    )
    Write-Host "Isto baixa e EXECUTA o WinUtil (Chris Titus Tech) de $Url." -ForegroundColor Yellow
    Write-Host "Requer internet e privilegios de administrador." -ForegroundColor Yellow

    # 1) Baixa para string (nao executa ainda)
    try {
        $script = Invoke-RestMethod -Uri $Url -ErrorAction Stop
    } catch {
        Write-Warning "Falha ao baixar o WinUtil: $($_.Exception.Message)"
        Pause-Script
        return
    }
    if ([string]::IsNullOrWhiteSpace($script)) {
        Write-Warning "Conteudo baixado vazio. Abortando."
        Pause-Script
        return
    }

    # 2) Calcula SHA256 do conteudo baixado
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($script)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    try   { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }   # SHA256::Create() e' IDisposable
    Write-Host ("Tamanho: {0:N0} bytes | SHA256: {1}" -f $bytes.Length, $hash) -ForegroundColor Cyan

    # 3) Pin opcional: se um hash esperado foi informado, exige correspondencia
    if ($ExpectedSha256) {
        if ($hash -ne $ExpectedSha256.Trim().ToLowerInvariant()) {
            Write-Warning "SHA256 NAO corresponde ao esperado. Esperado: $ExpectedSha256. ABORTANDO por seguranca."
            Pause-Script
            return
        }
        Write-Host "SHA256 confere com o esperado." -ForegroundColor Green
    }

    if (-not (Confirm-Action -Prompt "Executar o WinUtil com o SHA256 acima ?")) {
        Write-Host "Cancelado." -ForegroundColor DarkGray
        Pause-Script
        return
    }
    try {
        & ([scriptblock]::Create($script))
    } catch {
        Write-Warning "Falha ao executar o WinUtil: $($_.Exception.Message)"
    }
    Pause-Script
}


# --- Aliases de verbo aprovado (retrocompat) ---
# As funcoes seguem com nome PT (o lint do projeto ignora PSUseApprovedVerbs de proposito);
# estes aliases so melhoram a descoberta no console (Get-Command New-*, Show-*, Restore-*).
Set-Alias -Name Restore-PontoRestauracao -Value Restaurar-PontoRestauracao -Force
Set-Alias -Name New-PontoRestauracao     -Value Criar-PontoRestauracao      -Force
Set-Alias -Name New-PlanoDeEnergia        -Value Criar-PlanoDeEnergia         -Force
Set-Alias -Name New-App                   -Value Criar-App                    -Force


# --- PARTE 3: LÓGICA DE EXECUÇÃO PRINCIPAL ---
# O script realmente começa a "fazer" algo a partir daqui.

# 3.1: Privilégios — checado por AÇÃO. O modo automatizado '-Acao Sincronizar'
# (robocopy) NÃO exige admin; antes um exit global aqui quebrava a Tarefa Agendada
# rodando como usuário comum. O gate de admin agora fica dentro do menu interativo.

# 3.2: PowerShell 7 indisponível (o relançamento, quando o pwsh.exe EXISTE, já
# acontece em PARTE 1.1 no topo do script). Se ainda estamos em PS 5.x aqui, é
# porque o pwsh.exe NÃO foi encontrado: oferecer instalação automática (1 prompt S/N)
# com cadeia de fallbacks (winget → MSI GitHub → aka.ms → zip portátil sem admin).
if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $IsRelaunched) {
    if ($Acao -ne 'Menu') {
        # Modo automatizado (Tarefa Agendada): NUNCA bloquear em prompt — robocopy roda no PS5.
        Write-Warning "PowerShell 7 não encontrado; seguindo no Windows PowerShell $($PSVersionTable.PSVersion) (modo automatizado)."
    }
    else {
        Write-Host "PowerShell 7 não foi encontrado nesta máquina. Este script precisa dele para funcionar plenamente." -ForegroundColor Yellow
        $resp = Read-Host "Instalar o PowerShell 7 automaticamente agora? (S/N)"
        if ($resp -and $resp.ToUpper() -eq 'S') {
            if (Install-PowerShell7) {
                $pwsh7 = Find-PwshPath
                if ($pwsh7) {
                    Write-Host "PowerShell 7 instalado. Relançando o script..." -ForegroundColor Green
                    try {
                        $null = Start-SyncMasterInPowerShell7 `
                            -PwshPath $pwsh7 `
                            -ScriptPath $PSCommandPath `
                            -BoundParameters $PSBoundParameters
                        return
                    }
                    catch {
                        Write-Warning ("PowerShell 7 instalado, mas o relançamento falhou: {0}" -f $_.Exception.Message)
                    }
                }
                else {
                    Write-Warning "Instalação concluída, mas o pwsh.exe não foi localizado. Reinicie o script manualmente."
                }
            }
            else {
                Write-Warning "A instalação automática falhou em todos os métodos. Abrindo o menu de atualização..."
                Menu-AtualizacaoPowerShell
                Write-Host "Por favor, reinicie o script após a atualização." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Ok. O script não pode continuar no Windows PowerShell 5.x." -ForegroundColor Yellow
        }
        Pause-Script
        exit
    }
}

# Se chegou aqui, está no PS7+ ou foi relançado. Vamos verificar se existe uma versão ainda mais nova.
Write-Host "Script em execução no PowerShell $($PSVersionTable.PSVersion)..." -ForegroundColor Green
$currentVersion = [version]$PSVersionTable.PSVersion.ToString()
$latestVersionString = Get-LatestPowerShellVersion
if ($latestVersionString) {
    $latestVersion = [version]$latestVersionString
    if ($currentVersion -lt $latestVersion) {
        Write-Host "Sua versão ($currentVersion) está desatualizada. A mais recente é $latestVersion." -ForegroundColor Yellow
        $resp = Read-Host "Deseja abrir o menu de atualização? (S/N)"
        if($resp -and $resp.ToUpper() -eq 'S'){
            Menu-AtualizacaoPowerShell
        }
    }
}

# 3.3: Lógica Principal (Menu ou Ação Direta)
switch ($Acao.ToUpper()) {
    'SINCRONIZAR' {
        Write-Host "Modo automatizado: Iniciando Sincronização..." -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($Origem) -or [string]::IsNullOrWhiteSpace($Destino)) {
            Registrar-Log "ERRO (Agendado): Parâmetros -Origem e -Destino são obrigatórios para a ação 'Sincronizar'."
            exit 1
        }
        # Engine V2 unica (mesma do menu interativo): nao-interativa (sem Confirm/Read-Host,
        # que travavam o antigo Executar-Robocopy numa tarefa agendada), com guard de
        # origem/destino e checagem de espaco UNC-aware embutidos nas presenters.
        if ($Modo -eq 'Bilateral') {
            # Espelhamento mutuo = /MIR nos dois sentidos (preserva semantica do modo antigo).
            Start-RobocopyEspelho -Origem $Origem  -Destino $Destino
            Start-RobocopyEspelho -Origem $Destino -Destino $Origem
        } else {
            Start-RobocopyUnilateralSeguro -Origem $Origem -Destino $Destino -PreservarTudo
        }
    }

    'MENU' {
        # Gate de admin: só o menu interativo exige elevação (faz reg/serviços/powercfg).
        if (-not (Test-IsAdmin)) {
            Write-Warning "ERRO: O menu interativo precisa ser executado como Administrador."
            Read-Host "Pressione Enter para fechar."
            exit
        }
        # Menu data-driven (Fase C): a tabela vem de Get-MenuPrincipal (modules\Menu.psm1).
        # O dispatch fica AQUI (escopo do launcher) porque acoes como Menu-Otimizacao/Executor/
        # Criar-App sao definidas neste .ps1 e nao seriam visiveis de dentro de um modulo.
        $entradas = Get-MenuPrincipal
        do {
            Show-MenuPrincipal -Entradas $entradas

            $escolha = Read-Host "Digite sua escolha e pressione Enter"
            Registrar-Log "Menu principal: opcao '$escolha'"

            $sel = $entradas | Where-Object { $_.Id -eq ([string]$escolha).ToUpper() } | Select-Object -First 1
            if (-not $sel) {
                Write-Warning "Opção inválida. Tente novamente."
                Pause-Script
                continue
            }
            if ($sel.Comando -eq '__SAIR__') {
                Write-Host "Encerrando script. Até logo, Eng. Ortiz." -ForegroundColor Green
                exit
            }
            # Despacha pelo nome da funcao (modulo OU definida neste launcher). try/catch isola a
            # acao: sem isto um throw da leaf (ex.: Require-Admin sem elevacao, ou funcao inexistente)
            # propagava e DERRUBAVA o loop do menu inteiro — o usuario era chutado do script.
            try {
                & $sel.Comando
            } catch {
                Write-Warning ("A ação '{0}' falhou: {1}" -f $sel.Comando, $_.Exception.Message)
                Registrar-Log ("ERRO na acao de menu '{0}': {1}" -f $sel.Comando, $_.Exception.Message)
                Pause-Script
            }
        } while ($true)
    }

    default {
        Write-Warning "Ação '$Acao' desconhecida. Use 'Sincronizar' ou 'Menu'."
        exit 1
    }
}




