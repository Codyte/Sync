# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L37    Pause-Local
#   L39    Clean-Temp
#   L87    STARTUPS (com seleção por números) =================================
#   L105   Get-Startups
#   L203   Parse-Selection
#   L244   Disable-StartupByNumber
#   L296   Enable-StartupByNumber
#   L347   Menu-Startups
#   L389   MEDICAO: observar antes/depois e guardar evidencia local ----------
#   L390   Get-ActivePowerPlan
#   L402   Get-DefenderStatus
#   L423   Get-PerformanceSnapshot
#   L522   Save-PerformanceSnapshot
#   L534   Compare-PerformanceSnapshot
#   L556   Compare-LatestPerformanceSnapshots
#   L577   Get-PageFileStatus
#   L599   New-PowerReport
#   L631   Invoke-DefenderQuickScan
#   L651   Invoke-DefenderPerformanceAnalysis
#   L679   Menu-DefenderPerformance
#   L710   ARMAZENAMENTO: Windows escolhe TRIM/Defrag pelo tipo do volume -------
#   L711   Invoke-StorageOptimization
#   L751   Storage-Maintenance
#   L779   Energia: Equilibrado por padrão; Alto Desempenho apenas sob demanda --
#   L780   Set-PowerPlan
#   L801   Power-CPU-Tune
# ======================= END NAV INDEX =======================

<#
    Otimizacao.psm1 — manutencao util e reversivel para Windows 10/11.
    Depende de Core.psm1 (Pause-Script, Confirm-Action, Require-Admin, Ensure-Dir).
#>

# Wrapper retrocompativel: o codigo legado chama Pause-Local; delega ao Pause-Script do Core.
function Pause-Local { Pause-Script }

function Clean-Temp {
        Require-Admin
        $paths = @()
        if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
            Write-Warning 'TEMP nao esta definido; temporarios do usuario nao foram limpos.'
        } else { $paths += $env:TEMP }
        if ([string]::IsNullOrWhiteSpace($env:WINDIR)) {
            Write-Warning 'WINDIR nao esta definido; temporarios do Windows nao foram limpos.'
        } else { $paths += (Join-Path $env:WINDIR 'Temp') }

        foreach ($p in ($paths | Sort-Object -Unique)) {
            try {
                if ($p -notmatch '^[A-Za-z]:[\\/]') {
                    Write-Warning "Caminho temporario nao absoluto ignorado: $p"
                    continue
                }
                $full = [IO.Path]::GetFullPath($p)
                if ($full -eq [IO.Path]::GetPathRoot($full)) {
                    Write-Warning "Raiz de volume recusada como caminho temporario: $full"
                    continue
                }
                if (-not (Test-Path -LiteralPath $full -PathType Container -ErrorAction Stop)) { continue }
                Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Warning ("Caminho temporario ignorado ({0}): {1}" -f $p,$_.Exception.Message)
            }
        }
        $dismStatus = 'Nao executado'
        try {
            # Dism.exe e nativo: exit != 0 NAO lanca. O catch so pega Dism.exe ausente;
            # o resultado real vem do $LASTEXITCODE (senao "concluida" mentia em falha).
            Dism.exe /Online /Cleanup-Image /StartComponentCleanup | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $dismStatus = 'OK'
                Write-Host "Temporários processados e Component Store limpo." -ForegroundColor Green
            } else {
                $dismStatus = "Falha($LASTEXITCODE)"
                Write-Warning ("DISM retornou código {0} — Component Store NÃO limpo (TEMP já foi limpo)." -f $LASTEXITCODE)
            }
        } catch {
            $dismStatus = 'Falha ao iniciar'
            Write-Warning ("DISM falhou: {0}" -f $_.Exception.Message)
        }
        Registrar-Log "Clean-Temp executado (TEMP processado; DISM=$dismStatus)"
}

# ===== STARTUPS (com seleção por números) =================================

# Folders e chaves de backup
$script:StartupsBackupKeyUser    = 'HKCU:\Software\_DisabledRun_Backup\User'
$script:StartupsBackupKeyMachine = 'HKCU:\Software\_DisabledRun_Backup\Machine'
$script:StartupFolderUser        = [Environment]::GetFolderPath('Startup')
$script:StartupFolderCommon      = [Environment]::GetFolderPath('CommonStartup')
$script:StartupFolderBackup      = Join-Path $env:ProgramData 'Startup_Disabled'
$script:StartupBackupUser        = Join-Path $script:StartupFolderBackup 'User'
$script:StartupBackupCommon      = Join-Path $script:StartupFolderBackup 'Common'
foreach ($d in @($script:StartupFolderBackup,$script:StartupBackupUser,$script:StartupBackupCommon)) {
    try { New-Item -ItemType Directory -Path $d -Force | Out-Null } catch { Write-Verbose $_.Exception.Message }
}





function Get-Startups {
<#
.SYNOPSIS
    Lista todos os itens de inicializacao (Registro Run + pastas Startup), ativos e desativados.
.DESCRIPTION
    Varre HKCU/HKLM Run e as pastas Startup (User/Common), mais os backups dos que foram
    desativados por este tool, retornando objetos com SourceType, Scope, Enabled, Name, Command.
    Itens desativados ficam no backup (Registro _DisabledRun_Backup ou pasta Startup_Disabled).
.OUTPUTS
    PSCustomObject[] — um por item, ON antes de OFF, ordenado por nome.
#>
    $items = @()

    # 1) Registro ON (HKCU/HKLM Run)
    $regPaths = @(
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';   Scope='User'},
        @{Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';   Scope='Machine'}
    )
    foreach ($rp in $regPaths) {
        try {
            $props = Get-ItemProperty -Path $rp.Path -ErrorAction Stop
            $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                $items += [pscustomobject]@{
                    SourceType = 'Registry'
                    Scope      = $rp.Scope
                    Enabled    = $true
                    Name       = $_.Name
                    Command    = $_.Value
                    CurrentDir = $rp.Path
                    RestoreDir = $null
                }
            }
        } catch { Write-Verbose $_.Exception.Message }
    }

    # 2) Pastas Startup ON (User/Common)
    foreach ($dir in @($script:StartupFolderUser,$script:StartupFolderCommon)) {
        if (Test-Path $dir) {
            Get-ChildItem -Path $dir -File | ForEach-Object {
                $scope = if ($dir -eq $script:StartupFolderUser) { 'UserFolder' } else { 'CommonFolder' }
                $items += [pscustomobject]@{
                    SourceType = 'Folder'
                    Scope      = $scope
                    Enabled    = $true
                    Name       = $_.Name
                    Command    = $_.FullName
                    CurrentDir = $dir
                    RestoreDir = $null
                }
            }
        }
    }

    # 3) Registro OFF (backup User/Machine)
    $bkRegs = @(
        @{Path=$script:StartupsBackupKeyUser;    Scope='User'},
        @{Path=$script:StartupsBackupKeyMachine; Scope='Machine'}
    )
    foreach ($bk in $bkRegs) {
        if (Test-Path $bk.Path) {
            $props = Get-ItemProperty -Path $bk.Path
            $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                $items += [pscustomobject]@{
                    SourceType = 'Registry'
                    Scope      = $bk.Scope          # para restaurar no alvo certo
                    Enabled    = $false
                    Name       = $_.Name
                    Command    = $_.Value
                    CurrentDir = $bk.Path
                    RestoreDir = $null
                }
            }
        }
    }

    # 4) Pastas Startup OFF (backup User/Common)
    foreach ($pair in @(@{Dir=$script:StartupBackupUser;   Scope='UserFolder';   Restore=$script:StartupFolderUser},
                        @{Dir=$script:StartupBackupCommon; Scope='CommonFolder'; Restore=$script:StartupFolderCommon})) {
        if (Test-Path $pair.Dir) {
            Get-ChildItem -Path $pair.Dir -File | ForEach-Object {
                $items += [pscustomobject]@{
                    SourceType = 'Folder'
                    Scope      = $pair.Scope
                    Enabled    = $false
                    Name       = $_.Name
                    Command    = $_.FullName
                    CurrentDir = $pair.Dir          # onde está agora (backup)
                    RestoreDir = $pair.Restore      # para onde deve voltar
                }
            }
        }
    }

    # Ordena: ON primeiro, depois OFF
    $items | Sort-Object @{ Expression = 'Enabled'; Descending = $true }, Name
}

# Parser de seleção: "1 2 5-7,10" (compatível PS 5/7)
function Parse-Selection {
<#
.SYNOPSIS
    Converte uma string de selecao ("1 3 5-7,10") em uma lista de inteiros unica e ordenada.
.DESCRIPTION
    Aceita numeros soltos e intervalos a-b, separados por espaco, virgula ou ponto-e-virgula.
    Deduplica, ordena e descarta tudo fora de [1..Max] e intervalos invertidos.
.PARAMETER Selection
    Texto digitado pelo usuario (ex.: "1 3 5-7,10").
.PARAMETER Max
    Maior indice valido (limite superior do intervalo aceito).
.EXAMPLE
    Parse-Selection -Selection '1 3 5-7' -Max 10   # => 1,3,5,6,7
#>
    param(
        [string]$Selection,
        [int]$Max
    )
    # usa HashSet para deduplicar, mas materializa via enumeração (sem LINQ)
    $set = New-Object 'System.Collections.Generic.HashSet[int]'

    foreach ($token in ($Selection -split '[,; ]+' | Where-Object { $_ })) {
        if ($token -match '^\d+$') {
            $n = [int]$token
            if ($n -ge 1 -and $n -le $Max) { [void]$set.Add($n) }
        }
        elseif ($token -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -le $b) {
                for ($i = $a; $i -le $b; $i++) {
                    if ($i -ge 1 -and $i -le $Max) { [void]$set.Add($i) }
                }
            }
        }
    }

    # materializa sem ToArray(): @($set) já enumera; ordena antes de devolver
    return ,(@($set) | Sort-Object)
}


function Disable-StartupByNumber {
    param([int[]]$Indexes)
    Require-Admin
    Registrar-Log ("Disable-StartupByNumber: indices " + ($Indexes -join ','))
    $list = Get-Startups
    $i=0; $map=@{}
    foreach ($it in $list) { $i++; $map[$i] = $it }

    foreach ($idx in $Indexes) {
        $it = $map[$idx]
        if (-not $it) { Write-Warning "Índice $idx inválido."; continue }
        if (-not $it.Enabled) { Write-Host ("[{0}] {1} já está OFF." -f $idx,$it.Name) -ForegroundColor Yellow; continue }

        if ($it.SourceType -eq 'Registry') {
            # --- Registro: mover valor para chave de backup (User/Machine) ---
            $destKey = if ($it.Scope -eq 'Machine') { $script:StartupsBackupKeyMachine } else { $script:StartupsBackupKeyUser }
            if ($null -ne (Get-ItemProperty -Path $destKey -Name $it.Name -ErrorAction SilentlyContinue)) {
                Write-Warning ("[{0}] Backup de '{1}' ja existe; item preservado." -f $idx,$it.Name)
                continue
            }
            Ensure-Dir $destKey
            try {
                New-ItemProperty -Path $destKey -Name $it.Name -Value $it.Command -PropertyType String -ErrorAction Stop | Out-Null
                Remove-ItemProperty -Path $it.CurrentDir -Name $it.Name -Force -ErrorAction Stop
                Write-Host ("[{0}] {1} -> DESABILITADO (backup: {2})" -f $idx,$it.Name,$destKey) -ForegroundColor Yellow
            } catch {
                Write-Warning ("[{0}] Falha ao desabilitar '{1}' (Registro): {2}" -f $idx,$it.Name,$_.Exception.Message)
            }
        } else {
            # --- Pasta Startup: mover .lnk para backup; fallback rename; último recurso remove ---
            $src = $it.Command
            $bkDir = if ($it.Scope -eq 'CommonFolder') { $script:StartupBackupCommon } else { $script:StartupBackupUser }
            Ensure-Dir $bkDir
            $dst = Join-Path $bkDir $it.Name
            if (Test-Path -LiteralPath $dst) {
                Write-Warning ("[{0}] Backup de '{1}' ja existe; atalho preservado." -f $idx,$it.Name)
                continue
            }
            if (-not (Test-Path -LiteralPath $src)) {
                Write-Warning ("[{0}] Atalho '{1}' nao foi encontrado." -f $idx,$it.Name)
                continue
            }
            try {
                Move-Item -LiteralPath $src -Destination $dst -ErrorAction Stop
                Write-Host ("[{0}] {1} -> DESABILITADO (movido para {2})" -f $idx,$it.Name,$bkDir) -ForegroundColor Yellow
            } catch {
                Write-Warning ("[{0}] Falha ao desabilitar '{1}' (atalho preservado): {2}" -f $idx,$it.Name,$_.Exception.Message)
            }
        }
    }
}

function Enable-StartupByNumber {
    param([int[]]$Indexes)
    Require-Admin
    Registrar-Log ("Enable-StartupByNumber: indices " + ($Indexes -join ','))
    $list = Get-Startups
    $i=0; $map=@{}
    foreach ($it in $list) { $i++; $map[$i] = $it }

    foreach ($idx in $Indexes) {
        $it = $map[$idx]
        if (-not $it) { Write-Warning "Índice $idx inválido."; continue }

        if ($it.Enabled) { Write-Host ("{0} já está ON." -f $it.Name) -ForegroundColor Green; continue }

        if ($it.SourceType -eq 'Registry') {
            # restaurar para HKCU/HKLM Run conforme Scope
            $destKey = if ($it.Scope -eq 'Machine') { 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' } else { 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
            $bkKey   = if ($it.Scope -eq 'Machine') { $script:StartupsBackupKeyMachine } else { $script:StartupsBackupKeyUser }
            if ($null -ne (Get-ItemProperty -Path $destKey -Name $it.Name -ErrorAction SilentlyContinue)) {
                Write-Warning ("'{0}' ja existe em {1}; backup preservado." -f $it.Name,$destKey)
                continue
            }
            try {
                New-Item -Path $destKey -Force -ErrorAction Stop | Out-Null
                New-ItemProperty -Path $destKey -Name $it.Name -Value $it.Command -PropertyType String -ErrorAction Stop | Out-Null
                Remove-ItemProperty -Path $bkKey -Name $it.Name -Force -ErrorAction SilentlyContinue
                Write-Host ("[{0}] {1} -> REATIVADO em {2}" -f $idx,$it.Name,$destKey) -ForegroundColor Green
            } catch {
                Write-Warning ("Falha ao reativar '{0}': {1}" -f $it.Name, $_.Exception.Message)
            }
        } else {
            # Folder: mover do backup para a pasta de origem (RestoreDir)
            $targetDir = $it.RestoreDir
            if (-not $targetDir) {
                $targetDir = if ($it.Scope -eq 'CommonFolder') { $script:StartupFolderCommon } else { $script:StartupFolderUser }
            }
            $target = Join-Path $targetDir $it.Name
            if (Test-Path -LiteralPath $target) {
                Write-Warning ("'{0}' ja existe em {1}; backup preservado." -f $it.Name,$targetDir)
                continue
            }
            try {
                Move-Item -LiteralPath $it.Command -Destination $target -ErrorAction Stop
                Write-Host ("[{0}] {1} -> REATIVADO em {2}" -f $idx,$it.Name,$targetDir) -ForegroundColor Green
            } catch {
                Write-Warning ("Falha ao reativar '{0}': {1}" -f $it.Name, $_.Exception.Message)
            }
        }
    }
}

function Menu-Startups {
    do {
        Clear-Host
        Write-Host "--- STARTUPS ---" -ForegroundColor Cyan

        $list = Get-Startups
        $i=0
        foreach ($it in $list) {
            $i++
            $onoff = if ($it.Enabled) { 'ON ' } else { 'off' }
            $where = if ($it.SourceType -eq 'Registry') {
                if ($it.Enabled) { $it.CurrentDir } else { "Backup($($it.Scope))" }
            } else {
                # Pasta: mostra o caminho EXATO do atalho
                if ($it.Enabled) { $it.Command } else { $it.Command }  # quando OFF, $it.Command já aponta p/ backup
            }
            Write-Host ("{0,3}. [{1}] {2}  ->  {3}" -f $i, $onoff, $it.Name, $where)
        }

        Write-Host ""
        Write-Host "D) Desabilitar por número(s)   R) Reativar por número(s)   Q) Voltar"
        $choice = Read-Host "Escolha"

        switch ($choice.ToUpper()) {
            'D' {
                $sel = Read-Host "Informe números (ex.: 1 3 5-7)"
                $idx = Parse-Selection -Selection $sel -Max $list.Count
                if ($idx.Count -gt 0) { Disable-StartupByNumber -Indexes $idx }
                Pause-Local
            }
            'R' {
                $sel = Read-Host "Informe números (ex.: 2 4 10-12)"
                $idx = Parse-Selection -Selection $sel -Max $list.Count
                if ($idx.Count -gt 0) { Enable-StartupByNumber -Indexes $idx }
                Pause-Local
            }
            'Q' { return }
        }
    } while ($true)
}
# ========================================================================

# ---------- MEDICAO: observar antes/depois e guardar evidencia local ----------
function Get-ActivePowerPlan {
    try {
        $output = @(powercfg /getactivescheme 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        $text = ($output -join ' ').Trim()
        if ($text -match '\(([^)]+)\)') { return $Matches[1] }
        return $text
    } catch {
        return $null
    }
}

function Get-DefenderStatus {
    $command = Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{ RealTimeProtectionEnabled = $null; SignatureAgeDays = $null }
    }
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        $age = $null
        if ($status.AntivirusSignatureLastUpdated) {
            $age = [Math]::Round(((Get-Date) - [datetime]$status.AntivirusSignatureLastUpdated).TotalDays, 1)
        }
        return [pscustomobject]@{
            RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
            SignatureAgeDays          = $age
        }
    } catch {
        Write-Verbose ("Microsoft Defender indisponivel: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{ RealTimeProtectionEnabled = $null; SignatureAgeDays = $null }
    }
}

function Get-PerformanceSnapshot {
    [CmdletBinding()]
    param(
        [ValidateRange(1,10)][int]$CpuSampleCount = 3,
        [ValidateRange(0,10)][int]$CpuSampleIntervalSeconds = 1
    )

    $cpuSamples = @()
    for ($sample = 1; $sample -le $CpuSampleCount; $sample++) {
        try {
            $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor `
                -Filter "Name='_Total'" -ErrorAction Stop
            if ($null -ne $cpu.PercentProcessorTime) { $cpuSamples += [double]$cpu.PercentProcessorTime }
        } catch { Write-Verbose $_.Exception.Message }
        if ($sample -lt $CpuSampleCount -and $CpuSampleIntervalSeconds -gt 0) {
            Start-Sleep -Seconds $CpuSampleIntervalSeconds
        }
    }
    $os = $disk = $computer = $hotfix = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    } catch { Write-Verbose $_.Exception.Message }
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk `
            -Filter ("DeviceID='{0}'" -f $env:SystemDrive) -ErrorAction Stop
    } catch { Write-Verbose $_.Exception.Message }
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    } catch { Write-Verbose $_.Exception.Message }
    try {
        $hotfix = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
            Sort-Object InstalledOn -Descending | Select-Object -First 1
    } catch { Write-Verbose $_.Exception.Message }

    $memoryTotalMB = $memoryUsedMB = $memoryUsedPercent = $uptimeHours = $null
    if ($os -and [double]$os.TotalVisibleMemorySize -gt 0) {
        $memoryTotalMB = [Math]::Round([double]$os.TotalVisibleMemorySize / 1024, 1)
        $memoryUsedMB = [Math]::Round(([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) / 1024, 1)
        $memoryUsedPercent = [Math]::Round(
            (([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) /
                [double]$os.TotalVisibleMemorySize) * 100, 1)
        if ($os.LastBootUpTime) {
            $uptimeHours = [Math]::Round(((Get-Date) - [datetime]$os.LastBootUpTime).TotalHours, 1)
        }
    }

    $driveSizeGB = $driveFreeGB = $driveFreePercent = $null
    if ($disk -and [double]$disk.Size -gt 0) {
        $driveSizeGB = [Math]::Round([double]$disk.Size / 1GB, 1)
        $driveFreeGB = [Math]::Round([double]$disk.FreeSpace / 1GB, 1)
        $driveFreePercent = [Math]::Round(([double]$disk.FreeSpace / [double]$disk.Size) * 100, 1)
    }

    $lastHotFixDate = $null
    if ($hotfix -and $hotfix.InstalledOn) {
        try { $lastHotFixDate = ([datetime]$hotfix.InstalledOn).ToString('o') }
        catch { $lastHotFixDate = [string]$hotfix.InstalledOn }
    }

    $topProcesses = @()
    try {
        $topProcesses = @(Get-Process -ErrorAction Stop | Sort-Object WorkingSet64 -Descending |
            Select-Object -First 5 | ForEach-Object {
                [pscustomobject]@{
                    Name        = $_.ProcessName
                    Id          = $_.Id
                    WorkingSetMB = [Math]::Round([double]$_.WorkingSet64 / 1MB, 1)
                }
            })
    } catch { Write-Verbose $_.Exception.Message }

    $defender = Get-DefenderStatus
    [pscustomobject]@{
        SchemaVersion                 = 1
        CapturedAt                    = (Get-Date).ToString('o')
        ComputerName                  = $env:COMPUTERNAME
        CpuPercent                    = if ($cpuSamples.Count -gt 0) {
            [Math]::Round([double](($cpuSamples | Measure-Object -Average).Average), 1)
        } else { $null }
        CpuSampleCount                = $cpuSamples.Count
        MemoryTotalMB                 = $memoryTotalMB
        MemoryUsedMB                  = $memoryUsedMB
        MemoryUsedPercent             = $memoryUsedPercent
        SystemDrive                   = $env:SystemDrive
        SystemDriveSizeGB             = $driveSizeGB
        SystemDriveFreeGB             = $driveFreeGB
        SystemDriveFreePercent        = $driveFreePercent
        UptimeHours                   = $uptimeHours
        StartupEnabledCount           = @(Get-Startups | Where-Object Enabled).Count
        AutomaticManagedPageFile      = if ($computer) { $computer.AutomaticManagedPagefile } else { $null }
        LastHotFixId                  = if ($hotfix) { $hotfix.HotFixID } else { $null }
        LastHotFixInstalledOn         = $lastHotFixDate
        DefenderRealTimeProtection    = $defender.RealTimeProtectionEnabled
        DefenderSignatureAgeDays      = $defender.SignatureAgeDays
        ActivePowerPlan               = Get-ActivePowerPlan
        TopMemoryProcesses            = $topProcesses
    }
}

function Save-PerformanceSnapshot {
    [CmdletBinding()]
    param([AllowNull()][object]$Snapshot)

    if ($null -eq $Snapshot) { $Snapshot = Get-PerformanceSnapshot }
    $directory = Get-SyncMasterDataDir -SubPasta 'Reports\Performance'
    $path = Join-Path $directory ("performance_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    $Snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
    Registrar-Log ("Snapshot de desempenho salvo: {0}" -f $path)
    return $path
}

function Compare-PerformanceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Before,
        [Parameter(Mandatory)][object]$After
    )

    $getDelta = {
        param($BeforeValue, $AfterValue)
        if ($null -eq $BeforeValue -or $null -eq $AfterValue) { return $null }
        return [Math]::Round(([double]$AfterValue - [double]$BeforeValue), 2)
    }
    [pscustomobject]@{
        BeforeCapturedAt           = $Before.CapturedAt
        AfterCapturedAt            = $After.CapturedAt
        CpuPercentDelta            = & $getDelta $Before.CpuPercent $After.CpuPercent
        MemoryUsedPercentDelta     = & $getDelta $Before.MemoryUsedPercent $After.MemoryUsedPercent
        SystemDriveFreeGBDelta     = & $getDelta $Before.SystemDriveFreeGB $After.SystemDriveFreeGB
        StartupEnabledCountDelta   = & $getDelta $Before.StartupEnabledCount $After.StartupEnabledCount
    }
}

function Compare-LatestPerformanceSnapshots {
    [CmdletBinding()]
    param()

    $directory = Get-SyncMasterDataDir -SubPasta 'Reports\Performance'
    $files = @(Get-ChildItem -LiteralPath $directory -Filter 'performance_*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 2)
    if ($files.Count -lt 2) {
        Write-Warning 'Sao necessarios pelo menos dois snapshots para comparar.'
        return $null
    }
    try {
        $after = Get-Content -LiteralPath $files[0].FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $before = Get-Content -LiteralPath $files[1].FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return Compare-PerformanceSnapshot -Before $before -After $after
    } catch {
        Write-Warning ("Falha ao comparar snapshots: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Get-PageFileStatus {
    [CmdletBinding()]
    param()

    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $usage = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
        $allocated = ($usage | Measure-Object AllocatedBaseSize -Sum).Sum
        $current = ($usage | Measure-Object CurrentUsage -Sum).Sum
        $peak = ($usage | Measure-Object PeakUsage -Sum).Sum
        [pscustomobject]@{
            AutomaticManaged = [bool]$computer.AutomaticManagedPagefile
            AllocatedMB      = if ($null -eq $allocated) { 0 } else { [int64]$allocated }
            CurrentUsageMB   = if ($null -eq $current) { 0 } else { [int64]$current }
            PeakUsageMB      = if ($null -eq $peak) { 0 } else { [int64]$peak }
        }
    } catch {
        Write-Warning ("Falha ao consultar o arquivo de paginacao: {0}" -f $_.Exception.Message)
        return $null
    }
}

function New-PowerReport {
    [CmdletBinding()]
    param(
        [ValidateSet('Energy','Battery')][string]$Type = 'Energy',
        [ValidateRange(10,300)][int]$DurationSeconds = 60
    )

    if ($Type -eq 'Energy') { Require-Admin }
    $directory = Get-SyncMasterDataDir -SubPasta 'Reports\Performance'
    $path = Join-Path $directory ("power_{0}_{1}.html" -f $Type.ToLowerInvariant(), (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    try {
        if ($Type -eq 'Energy') {
            powercfg /energy /output $path /duration $DurationSeconds | Out-Null
        } else {
            powercfg /batteryreport /output $path | Out-Null
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("powercfg retornou codigo {0}; relatorio nao gerado." -f $LASTEXITCODE)
            return $null
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-Warning 'powercfg terminou sem criar o relatorio esperado.'
            return $null
        }
        Registrar-Log ("Relatorio powercfg salvo: {0}" -f $path)
        return $path
    } catch {
        Write-Warning ("Falha ao gerar relatorio de energia: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Invoke-DefenderQuickScan {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param()

    if (-not (Get-Command Start-MpScan -ErrorAction SilentlyContinue)) {
        Write-Warning 'Start-MpScan nao esta disponivel neste sistema.'
        return $false
    }
    Require-Admin
    if (-not $PSCmdlet.ShouldProcess('Microsoft Defender', 'Executar verificacao rapida')) { return $false }
    try {
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Registrar-Log 'Microsoft Defender: verificacao rapida concluida.'
        return $true
    } catch {
        Write-Warning ("Falha na verificacao rapida do Microsoft Defender: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Invoke-DefenderPerformanceAnalysis {
    [CmdletBinding()]
    param()

    if (-not (Get-Command New-MpPerformanceRecording -ErrorAction SilentlyContinue) -or
        -not (Get-Command Get-MpPerformanceReport -ErrorAction SilentlyContinue)) {
        Write-Warning 'O analisador de desempenho do Microsoft Defender nao esta disponivel.'
        return $null
    }
    Require-Admin
    $directory = Get-SyncMasterDataDir -SubPasta 'Reports\Performance'
    $stem = "defender_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
    $tracePath = Join-Path $directory ($stem + '.etl')
    $reportPath = Join-Path $directory ($stem + '.json')
    try {
        Write-Host 'Reproduza a carga lenta e pressione ENTER para encerrar a gravacao.' -ForegroundColor Yellow
        New-MpPerformanceRecording -RecordTo $tracePath -ErrorAction Stop
        $report = Get-MpPerformanceReport -Path $tracePath -TopFiles 10 -TopExtensions 10 `
            -TopProcesses 10 -TopScans 10 -Raw -ErrorAction Stop
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8 -ErrorAction Stop
        Registrar-Log ("Analise de desempenho do Defender salva: {0}" -f $reportPath)
        return [pscustomobject]@{ TracePath = $tracePath; ReportPath = $reportPath }
    } catch {
        Write-Warning ("Falha na analise de desempenho do Microsoft Defender: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Menu-DefenderPerformance {
    do {
        Clear-Host
        Write-Host '--- Microsoft Defender ---' -ForegroundColor Cyan
        Write-Host '1) Verificacao rapida contra malware'
        Write-Host '2) Gravar e analisar impacto de desempenho do Defender'
        Write-Host '3) Abrir Seguranca do Windows'
        Write-Host 'Q) Voltar'
        $choice = Read-Host 'Escolha'
        switch ($choice.ToUpper()) {
            '1' {
                if (Confirm-Action 'Executar agora a verificacao rapida do Microsoft Defender?') {
                    [void](Invoke-DefenderQuickScan -Confirm:$false)
                }
                Pause-Local
            }
            '2' {
                if (Confirm-Action 'Gravar uma carga para diagnosticar o impacto do Defender?') {
                    $result = Invoke-DefenderPerformanceAnalysis
                    if ($result) { $result | Format-List }
                }
                Pause-Local
            }
            '3' { Start-Process 'ms-settings:windowsdefender'; Pause-Local }
            'Q' { return }
            default { Write-Warning 'Opcao invalida.'; Pause-Local }
        }
    } while ($true)
}


# ---------- ARMAZENAMENTO: Windows escolhe TRIM/Defrag pelo tipo do volume ----------
function Invoke-StorageOptimization {
    [CmdletBinding()]
    param([ValidateSet('Analyze','Optimize')][string]$Mode = 'Analyze')

    Require-Admin
    try {
        $volumes = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter })
    } catch {
        Write-Warning ("Falha ao listar volumes: {0}" -f $_.Exception.Message)
        return $false
    }
    if ($volumes.Count -eq 0) {
        Write-Warning 'Nenhum volume fixo com letra foi encontrado.'
        return $false
    }

    $falhas = 0
    foreach ($volume in $volumes) {
        try {
            if ($Mode -eq 'Analyze') {
                Optimize-Volume -DriveLetter $volume.DriveLetter -Analyze -Verbose -ErrorAction Stop | Out-Null
            } else {
                # Sem flag, o próprio Windows usa ReTrim em SSD e Defrag em HDD.
                Optimize-Volume -DriveLetter $volume.DriveLetter -Verbose -ErrorAction Stop | Out-Null
            }
            Registrar-Log ("Optimize-Volume {0}: {1}" -f $Mode,$volume.DriveLetter)
        } catch {
            $falhas++
            Write-Warning ("Volume {0}: {1}" -f $volume.DriveLetter,$_.Exception.Message)
        }
    }

    if ($falhas -gt 0) {
        Write-Warning ("Operação concluída com falha em {0} volume(s)." -f $falhas)
        return $false
    }
    Write-Host ("{0} concluído em {1} volume(s)." -f $Mode,$volumes.Count) -ForegroundColor Green
    return $true
}

function Storage-Maintenance {
    do {
        Clear-Host
        Write-Host '--- Manutenção de Armazenamento ---' -ForegroundColor Cyan
        Write-Host '1) Analisar volumes fixos (sem alterações)'
        Write-Host '2) Otimizar volumes fixos automaticamente (TRIM/Defrag)'
        Write-Host '3) Consultar estado do TRIM'
        Write-Host 'Q) Voltar'
        $choice = Read-Host 'Escolha'
        switch ($choice.ToUpper()) {
            '1' { [void](Invoke-StorageOptimization -Mode Analyze); Pause-Local }
            '2' {
                if (Confirm-Action 'Otimizar agora todos os volumes fixos?') {
                    [void](Invoke-StorageOptimization -Mode Optimize)
                }
                Pause-Local
            }
            '3' {
                fsutil behavior query DisableDeleteNotify
                if ($LASTEXITCODE -ne 0) { Write-Warning ("fsutil retornou código {0}." -f $LASTEXITCODE) }
                Pause-Local
            }
            'Q' { return }
            default { Write-Warning 'Opção inválida.'; Pause-Local }
        }
    } while ($true)
}

# ---------- Energia: Equilibrado por padrão; Alto Desempenho apenas sob demanda ----------
function Set-PowerPlan {
    [CmdletBinding()]
    param([ValidateSet('Balanced','HighPerformance')][string]$Plan = 'Balanced')

    $scheme = if ($Plan -eq 'Balanced') { 'SCHEME_BALANCED' } else { 'SCHEME_MIN' }
    $label = if ($Plan -eq 'Balanced') { 'Equilibrado' } else { 'Alto desempenho' }
    try {
        powercfg /setactive $scheme | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("powercfg retornou código {0}; plano não alterado." -f $LASTEXITCODE)
            return $false
        }
    } catch {
        Write-Warning ("Falha ao executar powercfg: {0}" -f $_.Exception.Message)
        return $false
    }
    Registrar-Log ("Plano de energia ativado: {0}" -f $label)
    Write-Host ("Plano de energia: {0}." -f $label) -ForegroundColor Green
    return $true
}

function Power-CPU-Tune {
    do {
        Clear-Host
        Write-Host '--- Energia/CPU ---' -ForegroundColor Cyan
        Write-Host '1) Equilibrado (recomendado para uso geral)'
        Write-Host '2) Alto desempenho (carga sustentada; maior consumo e calor)'
        Write-Host '3) Relatorio de eficiencia energetica (60 segundos)'
        Write-Host '4) Relatorio de bateria'
        Write-Host '5) Consultar arquivo de paginacao (sem alterar)'
        Write-Host 'Q) Voltar'
        $choice = Read-Host 'Escolha'
        switch ($choice.ToUpper()) {
            '1' { [void](Set-PowerPlan -Plan Balanced); Pause-Local }
            '2' {
                if (Confirm-Action 'Ativar Alto desempenho para uma carga sustentada?') {
                    [void](Set-PowerPlan -Plan HighPerformance)
                }
                Pause-Local
            }
            '3' {
                Write-Host 'Para um resultado util, feche programas e mantenha o computador ocioso durante a coleta.' -ForegroundColor Yellow
                $path = New-PowerReport -Type Energy
                if ($path) { Write-Host ("Relatorio salvo em: {0}" -f $path) -ForegroundColor Green }
                Pause-Local
            }
            '4' {
                $path = New-PowerReport -Type Battery
                if ($path) { Write-Host ("Relatorio salvo em: {0}" -f $path) -ForegroundColor Green }
                Pause-Local
            }
            '5' { Get-PageFileStatus | Format-List; Pause-Local }
            'Q' { return }
            default { Write-Warning 'Opção inválida.'; Pause-Local }
        }
    } while ($true)
}

Set-Alias -Name Clear-Temp -Value Clean-Temp -Scope Script -Force

Export-ModuleMember -Function Pause-Local, Clean-Temp, Get-Startups, Parse-Selection, `
    Disable-StartupByNumber, Enable-StartupByNumber, Menu-Startups, `
    Get-PerformanceSnapshot, Save-PerformanceSnapshot, Compare-PerformanceSnapshot, `
    Compare-LatestPerformanceSnapshots, Get-PageFileStatus, New-PowerReport, `
    Invoke-DefenderQuickScan, Invoke-DefenderPerformanceAnalysis, Menu-DefenderPerformance, `
    Invoke-StorageOptimization, Storage-Maintenance, Set-PowerPlan, Power-CPU-Tune `
    -Alias Clear-Temp
