# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L32    PARTE 1: BLOCO DE PARÂMETROS ÚNICO ---
#   L50    New-SyncMasterRelaunchArguments
#   L76    Start-SyncMasterInPowerShell7
#   L103   PARTE 1.1: Relançamento automático em PowerShell 7+ (compatível PS 5)
#   L146   PARTE 2: REGIÃO CENTRALIZADA DE FUNÇÕES ---
#   L221   Menu-Otimizacao
#   L253   Criar-PontoRestauracao
#   L338   Restaurar-PontoRestauracao
#   L473   Menu-LimpezaDisco
#   L528   Utilitários robustos ===============================================
#   L549   Menu-ReparoSistema
#   L577   Menu-Desempenho
#   L642   Menu-GerenciarAgentes
#   L680   Gerenciar-ServicoDeAgente
#   L730   Menu-Ferramentas
#   L758   Utilitário: enviar arquivo para a Lixeira (PS 5/7) ---
#   L793   Criar-App
#   L862   Aliases de verbo aprovado (retrocompat) ---
#   L870   PARTE 3: LÓGICA DE EXECUÇÃO PRINCIPAL ---
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
        [Parameter(Mandatory)][System.Collections.IDictionary]$BoundParameters,
        [switch]$Elevate
    )

    $isAdmin = (
        [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $startSplat = @{
        FilePath         = $PwshPath
        ArgumentList     = New-SyncMasterRelaunchArguments -ScriptPath $ScriptPath -BoundParameters $BoundParameters
        WorkingDirectory = [IO.Path]::GetDirectoryName($ScriptPath)
        WindowStyle      = 'Normal'
        PassThru         = $true
    }
    if ($Elevate -or $isAdmin) { $startSplat['Verb'] = 'RunAs' }

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
        Write-Host "6 - Gerenciar Agentes de Monitoramento (MMA/AMA)" -ForegroundColor Magenta
        Write-Host "7 - Gerenciamento de Arquivos (Duplicatas, etc.)" -ForegroundColor Green
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
            "6" { Menu-GerenciarAgentes }
            "7" { Menu-GerenciamentoArquivos }
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
        Write-Host "1. Limpar temporários e componentes substituídos do Windows"
        Write-Host "2. Analisar ou otimizar unidades (TRIM/Defrag automático)"
        Write-Host "3. Abrir Sensor de Armazenamento do Windows"
        Write-Host "4. Abrir visão geral do armazenamento"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' { Clean-Temp; Pause-Script }
            '2' { Storage-Maintenance }
            '3' { Start-Process 'ms-settings:storagepolicies'; Pause-Script }
            '4' { Start-Process 'ms-settings:storagesense'; Pause-Script }
            'Q' { return }
            default {Write-Warning "Opção inválida."}
        }
    } while($true)
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
        Write-Host "6. WPA / Proteção de Software (diagnóstico e reparo oficial)"
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
            '6' { Menu-GerenciamentoWpa }
            'Q' { return }
            default {Write-Warning "Opção inválida."}
        }
    } while($true)
}
#endregion

#region SubMenu: Desempenho
function Menu-Desempenho {
    do {
        Clear-Host
        Write-Host "--- DESEMPENHO BASEADO EM MEDIÇÃO ---" -ForegroundColor Cyan
        Write-Host "1. Medir e salvar estado atual (antes/depois)"
        Write-Host "2. Comparar os dois últimos estados"
        Write-Host "3. Gerenciar programas de inicialização"
        Write-Host "4. Limpeza e manutenção de armazenamento"
        Write-Host "5. Energia, bateria e arquivo de paginação"
        Write-Host "6. Microsoft Defender (scan e análise de impacto)"
        Write-Host "7. Ajustar efeitos visuais"
        Write-Host "8. Configurações gráficas por aplicativo"
        Write-Host "9. Windows Update"
        Write-Host "10. Aplicativos instalados"
        Write-Host "11. Atividade de aplicativos em segundo plano"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' {
                $snapshot = Get-PerformanceSnapshot
                $path = Save-PerformanceSnapshot -Snapshot $snapshot
                $snapshot | Select-Object CapturedAt,CpuPercent,MemoryUsedPercent,SystemDriveFreeGB,
                    SystemDriveFreePercent,UptimeHours,StartupEnabledCount,AutomaticManagedPageFile,
                    LastHotFixId,DefenderRealTimeProtection,DefenderSignatureAgeDays,ActivePowerPlan |
                    Format-List
                if ($snapshot.TopMemoryProcesses) {
                    Write-Host 'Processos com maior uso de memória:' -ForegroundColor Cyan
                    $snapshot.TopMemoryProcesses | Format-Table -AutoSize
                }
                Write-Host ("Snapshot salvo em: {0}" -f $path) -ForegroundColor Green
                Pause-Script
            }
            '2' {
                $comparison = Compare-LatestPerformanceSnapshots
                if ($comparison) {
                    Write-Host 'Delta = depois - antes. CPU/RAM/startups menores e espaço livre maior são sinais favoráveis.' -ForegroundColor Cyan
                    $comparison | Format-List
                }
                Pause-Script
            }
            '3' { Menu-Startups }
            '4' { Menu-LimpezaDisco }
            '5' { Power-CPU-Tune }
            '6' { Menu-DefenderPerformance }
            '7' { Start-Process "SystemPropertiesPerformance.exe"; Pause-Script }
            '8' { Start-Process "ms-settings:display-advancedgraphics"; Pause-Script }
            '9' { Start-Process 'ms-settings:windowsupdate'; Pause-Script }
            '10' { Start-Process 'ms-settings:appsfeatures'; Pause-Script }
            '11' {
                if ([Environment]::OSVersion.Version.Build -ge 22000) {
                    Write-Host 'No Windows 11, abra as opções avançadas de cada aplicativo para ajustar a atividade em segundo plano.' -ForegroundColor Cyan
                    Start-Process 'ms-settings:appsfeatures'
                } else {
                    Start-Process 'ms-settings:privacy-backgroundapps'
                }
                Pause-Script
            }
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
    [CmdletBinding()]
    param (
        [string]$IconFile,
        [string]$ScriptPath
    )

    $converter = Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $converter) {
        Write-Error "Invoke-ps2exe não foi encontrado. Instale o módulo PS2EXE para o usuário atual."
        Pause-Script
        return
    }

    # Arquivo de origem (o próprio script) e saída.
    # $MyInvocation.MyCommand.Path e' NULO dentro de uma funcao (reflete a invocacao da
    # funcao, nao do script) -> ChangeExtension($null) lanca e -inputFile fica vazio.
    # $PSCommandPath e' o caminho do .ps1 em execucao; fallback p/ a entry exposta no topo.
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        $ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $env:SYNCMASTER_ENTRY }
    }
    if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        Write-Error "Não foi possível resolver o caminho do script para compilar."
        Pause-Script
        return
    }
    $ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
    $outputFile = [System.IO.Path]::ChangeExtension($ScriptPath, ".exe")
    $tempOutput = Join-Path ([IO.Path]::GetDirectoryName($outputFile)) (
        '.{0}-{1}.tmp.exe' -f [IO.Path]::GetFileNameWithoutExtension($outputFile), [guid]::NewGuid().ToString('N')
    )

    Write-Host "`n--- COMPILANDO SCRIPT ---" -ForegroundColor Cyan
    Write-Host "Conversor: $($converter.Source)"
    Write-Host "Origem:     $ScriptPath"
    Write-Host "Saída:      $outputFile"

    $argumentos = @{
        inputFile  = $ScriptPath
        outputFile = $tempOutput
    }

    # Ícone (opcional)
    if ($IconFile -and (Test-Path -LiteralPath $IconFile -PathType Leaf)) {
        $argumentos.iconFile = (Resolve-Path -LiteralPath $IconFile).Path
        Write-Host "Ícone aplicado: $IconFile"
    }

    # Execução do PS2EXE
    try {
        & $converter @argumentos -ErrorAction Stop
        if (-not $?) { throw 'O conversor retornou falha.' }
        if (-not (Test-Path -LiteralPath $tempOutput -PathType Leaf)) { throw 'O conversor não criou o executável esperado.' }
        Move-Item -LiteralPath $tempOutput -Destination $outputFile -Force -ErrorAction Stop
        Write-Host "✔️ SUCESSO: EXE criado em '$outputFile'!" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ FALHA ao executar o conversor."
        Write-Error $_.Exception.Message
    }
    finally {
        if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue }
    }

    Pause-Script
}



# --- Aliases de verbo aprovado (retrocompat) ---
# As funcoes seguem com nome PT (o lint do projeto ignora PSUseApprovedVerbs de proposito);
# estes aliases so melhoram a descoberta no console (Get-Command New-*, Show-*, Restore-*).
Set-Alias -Name Restore-PontoRestauracao -Value Restaurar-PontoRestauracao -Force
Set-Alias -Name New-PontoRestauracao     -Value Criar-PontoRestauracao      -Force
Set-Alias -Name New-App                   -Value Criar-App                    -Force


# --- PARTE 3: LÓGICA DE EXECUÇÃO PRINCIPAL ---
# O script realmente começa a "fazer" algo a partir daqui.

# 3.1: Privilégios — checado por AÇÃO. O modo automatizado '-Acao Sincronizar'
# (robocopy) NÃO exige admin; antes um exit global aqui quebrava a Tarefa Agendada
# rodando como usuário comum. O gate de admin agora fica dentro do menu interativo.

# 3.2: PowerShell 7 indisponível (o relançamento, quando o pwsh.exe EXISTE, já
# acontece em PARTE 1.1 no topo do script). Se ainda estamos em PS 5.x aqui, é
# porque o pwsh.exe NÃO foi encontrado: oferecer instalação automática (1 prompt S/N)
# com cadeia de fallbacks (winget → MSI Microsoft/GitHub → ZIP oficial verificado).
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
        # O .cmd inicia sem interpolar caminhos em -Command; a elevação segura acontece aqui,
        # com o comando codificado por New-SyncMasterRelaunchArguments.
        if (-not (Test-IsAdmin)) {
            $currentPowerShell = Join-Path $PSHOME 'pwsh.exe'
            if (-not (Test-Path -LiteralPath $currentPowerShell)) {
                $currentPowerShell = (Get-Process -Id $PID).Path
            }
            Write-Host 'Solicitando permissao de Administrador para abrir o menu...' -ForegroundColor Yellow
            try {
                $null = Start-SyncMasterInPowerShell7 `
                    -PwshPath $currentPowerShell `
                    -ScriptPath $PSCommandPath `
                    -BoundParameters $PSBoundParameters `
                    -Elevate
                return
            }
            catch {
                Write-Warning ("Nao foi possivel elevar o menu: {0}" -f $_.Exception.Message)
                Read-Host "Pressione Enter para fechar."
                exit 1
            }
        }
        # Menu data-driven (Fase C): a tabela vem de Get-MenuPrincipal (modules\Menu.psm1).
        # O dispatch fica AQUI (escopo do launcher) porque acoes como Menu-Otimizacao/
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




