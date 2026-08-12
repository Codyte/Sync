<#
    Hardware.psm1 — monitoramento e diagnostico de hardware.
    Extraido do monolito legado (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

function Get-CpuRapido {
    try {
        # PercentProcessorTime já é calculado pelo sistema e atualiza ~1x/s
        $cim = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop |
               Where-Object { $_.Name -eq '_Total' }
        if ($cim) { return [math]::Round([double]$cim.PercentProcessorTime, 1) }
    } catch {  Write-Verbose $_.Exception.Message }
    return $null
}

function Get-MemUsoMB {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $total = [double]$os.TotalVisibleMemorySize
    $livre = [double]$os.FreePhysicalMemory
    [pscustomobject]@{
        UsadoMB = [math]::Round((($total - $livre) * 1024) / 1MB, 1)
        TotalMB = [math]::Round(($total * 1024) / 1MB, 1)
    }
}

function Get-DiscosInfo {
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" |
        ForEach-Object {
            $total = [double]($_.Size); $livre = [double]($_.FreeSpace); $usado = $total - $livre
            [pscustomobject]@{
                Name        = $_.DeviceID
                'Used (GB)' = [math]::Round($usado / 1GB, 2)
                'Free (GB)' = [math]::Round($livre / 1GB, 2)
                'Total (GB)'= [math]::Round($total / 1GB, 2)
                '% Used'    = if ($total -gt 0) { [math]::Round(($usado / $total) * 100, 1) } else { 0 }
            }
        } | Sort-Object Name
}

function Monitorar-Recursos {
    param(
        [ValidateRange(50,2147483647)][int]$IntervaloMs = 250, # 250-500ms baixa CPU do proprio monitor
        [ValidateRange(1,2147483647)][int]$CiclosDisco = 20    # atualiza os discos a cada N ciclos
    )

    $ciclo = 0
    $discosCache = Get-DiscosInfo

    # WindowWidth lanca em host sem console (ISE/redirecionado); fallback 80, igual ao
    # try/catch do CursorVisible logo abaixo. Sem isto, throw antes do try/finally.
    $largura = try { [Console]::WindowWidth } catch { 80 }
    if ($largura -lt 1) { $largura = 80 }
    $cursorVisivelOrig = $true
    try { $cursorVisivelOrig = [Console]::CursorVisible } catch { Write-Verbose $_.Exception.Message }

    Clear-Host
    try { [Console]::CursorVisible = $false } catch { Write-Verbose $_.Exception.Message }
    Write-Host ("--- MONITORAMENTO EM TEMPO REAL (Ctrl+C para sair) ---").PadRight($largura)

    # Pré-aloca linhas fixas para reescrever no mesmo lugar
    Write-Host ("CPU: ---% | RAM: ----/---- MB").PadRight($largura)
    Write-Host ("Discos: (atualiza a cada $CiclosDisco ciclos)").PadRight($largura)
    Write-Host ("").PadRight($largura)  # linha separadora

    # try/finally: Ctrl+C deixava o cursor invisivel e mal-posicionado; finally
    # restaura visibilidade e empurra o cursor para baixo do bloco antes de sair.
    try {
        while ($true) {
            try {
                $cpu = Get-CpuRapido
                if ($null -eq $cpu) { $cpu = 0 }

                $mem = Get-MemUsoMB

                # Atualiza discos com menos frequência
                if ($ciclo % $CiclosDisco -eq 0) {
                    $discosCache = Get-DiscosInfo
                }

                # Monta uma linha compacta de discos
                $discosStr = ($discosCache | ForEach-Object {
                    "{0}: {1}/{2} GB ({3}%)" -f $_.Name, $_.'Used (GB)', $_.'Total (GB)', $_.'% Used'
                }) -join " | "

                # Reposiciona o cursor e reescreve sem Clear-Host
                [Console]::SetCursorPosition(0,1)
                Write-Host ("CPU: {0:N1} % | RAM: {1:N1} / {2:N1} MB".PadRight($largura) -f $cpu, $mem.UsadoMB, $mem.TotalMB)
                [Console]::SetCursorPosition(0,2)
                Write-Host ("Discos: ".PadRight($largura))
                [Console]::SetCursorPosition(0,3)
                Write-Host ($discosStr.PadRight($largura))

                $ciclo++
                Start-Sleep -Milliseconds $IntervaloMs
            } catch {
                [Console]::SetCursorPosition(0,1)
                Write-Host ("[WARN] Erro ao coletar dados... tentando novamente.".PadRight($largura))
                Start-Sleep -Milliseconds ([Math]::Min(5000, $IntervaloMs + 500))
            }
        }
    } finally {
        try { [Console]::SetCursorPosition(0,4) } catch { Write-Verbose $_.Exception.Message }
        try { [Console]::CursorVisible = $cursorVisivelOrig } catch { Write-Verbose $_.Exception.Message }
    }
}

# PURA (Fase B): correlaciona discos do Win32_DiskDrive ($Base) com o Get-PhysicalDisk
# ($PhysicalDisks) por SerialNumber ou FriendlyName, devolvendo objetos enriquecidos com
# MediaType (SSD/HDD) e BusType quando ha' casamento. Sem CIM nem UI -> testavel.
function Merge-DiscoFisico {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Base,
        [AllowEmptyCollection()][object[]]$PhysicalDisks = @()
    )
    foreach ($d in $Base) {
        $match = $PhysicalDisks | Where-Object {
            ($_.SerialNumber -and $_.SerialNumber -eq $d.SerialNumber) -or
            ($_.FriendlyName -and $d.Model -and $d.Model -like "*$($_.FriendlyName)*")
        } | Select-Object -First 1
        [pscustomobject]@{
            Model          = $d.Model
            Interface      = if ($match) { $match.BusType } else { $d.InterfaceType }
            MediaType      = if ($match) { $match.MediaType } else { $null }   # SSD/HDD quando disponivel
            'Tamanho (GB)' = $d.'Tamanho (GB)'
            SerialNumber   = $d.SerialNumber
            Firmware       = $d.FirmwareRevision
        }
    }
}

function Diagnostico-Hardware {
    Clear-Host
    Write-Host "--- DIAGNÓSTICO DE HARDWARE E SISTEMA ---" -ForegroundColor Cyan

    # Sistema (CIM direto — Get-ComputerInfo varre TUDO e leva segundos)
    $osCim = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $csCim = Get-CimInstance Win32_ComputerSystem  -ErrorAction SilentlyContinue
    [pscustomobject]@{
        CsName         = $csCim.Name
        OsName         = $osCim.Caption
        OsVersion      = $osCim.Version
        OsArchitecture = $osCim.OSArchitecture
        CsSystemType   = $csCim.SystemType
        CsManufacturer = $csCim.Manufacturer
        CsModel        = $csCim.Model
    } | Format-List

    # Memória física
    Write-Host "`n--- MEMÓRIA FÍSICA ---" -ForegroundColor Cyan
    Get-CimInstance -ClassName Win32_PhysicalMemory |
        Select-Object Manufacturer, Speed,
            @{Name="Capacidade (GB)"; Expression = { [math]::Round(($_.Capacity/1GB), 2) }} |
        Format-Table -AutoSize

    # Unidades de disco (volumes/letras)
    Write-Host "`n--- UNIDADES DE DISCO ---" -ForegroundColor Cyan
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object @{N='Name';E={$_.DeviceID}},
                      @{N='Total (GB)';E={ [math]::Round(($_.Size/1GB),2) }},
                      @{N='Usado (GB)';E={ [math]::Round((($_.Size - $_.FreeSpace)/1GB),2) }},
                      @{N='Livre (GB)';E={ [math]::Round(($_.FreeSpace/1GB),2) }} |
        Sort-Object Name |
        Format-Table -AutoSize

    # Discos físicos (compatível PS7). Enriquecido com MediaType/BusType quando possível.
    Write-Host "`n--- DISCOS FÍSICOS ---" -ForegroundColor Cyan
    $fisicosBase = Get-CimInstance -ClassName Win32_DiskDrive |
        Select-Object DeviceID, Model, InterfaceType,
                      @{N='Tamanho (GB)';E={ [math]::Round(($_.Size/1GB),2) }},
                      SerialNumber, FirmwareRevision

    $temStorage = Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($temStorage) {
        $pd = Get-PhysicalDisk | Select-Object FriendlyName, SerialNumber, MediaType, BusType
        $saida = Merge-DiscoFisico -Base @($fisicosBase) -PhysicalDisks @($pd)   # correlacao pura, testada
        $saida | Format-Table -AutoSize
    }
    else {
        $fisicosBase |
            Select-Object Model, InterfaceType,
                          'Tamanho (GB)', SerialNumber, FirmwareRevision |
            Format-Table -AutoSize
    }

# --- MAPA DISCO → PARTIÇÃO → VOLUME ---
Write-Host "`n--- MAPA DISCO → PARTIÇÃO → VOLUME ---" -ForegroundColor Cyan
try {
    $drives = Get-CimInstance Win32_DiskDrive

    # Materializa a saída numa coleção; nada de pipe logo após "}".
    $map = foreach ($d in $drives) {
        $parts = Get-CimAssociatedInstance -InputObject $d -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue
        foreach ($p in $parts) {
            $vols = Get-CimAssociatedInstance -InputObject $p -ResultClassName Win32_LogicalDisk -ErrorAction SilentlyContinue
            foreach ($v in $vols) {
                [pscustomobject]@{
                    'Disco (Model)' = $d.Model
                    'Partição'      = $p.DeviceID
                    'Volume'        = $v.DeviceID
                    'Tamanho (GB)'  = [math]::Round(($v.Size/1GB),2)
                }
            }
        }
    }

    $map | Sort-Object 'Disco (Model)', 'Partição', 'Volume' | Format-Table -AutoSize
}
catch {
    Write-Warning "Não foi possível gerar o mapa de volumes: $($_.Exception.Message)"
}

    Pause-Script
}

function Get-CpuUsageRobusto {
    # 1) Tenta vários contadores
    $candidatos = @(
        '\Processor(_Total)\% Processor Time',
        '\Processor Information(_Total)\% Processor Time',
        '\Processor(_Total)\% Privileged Time',
        '\Processor Information(_Total)\% Privileged Time'
    )
    foreach ($ctr in $candidatos) {
        try {
            $cs = (Get-Counter -Counter $ctr -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop).CounterSamples
            if ($cs -and $null -ne $cs.CookedValue) { return [math]::Round([double]$cs.CookedValue, 1) }
        } catch {  Write-Verbose $_.Exception.Message }
    }

    # 2) Fallback por WMI/CIM formatado
    try {
        $cim = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop |
               Where-Object { $_.Name -eq '_Total' }
        if ($cim -and $null -ne $cim.PercentProcessorTime) {
            return [math]::Round([double]$cim.PercentProcessorTime, 1)
        }
    } catch {  Write-Verbose $_.Exception.Message }

    # 3) Último fallback: média de LoadPercentage
    try {
        $wmi = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $media = ($wmi | Measure-Object -Property LoadPercentage -Average).Average
        if ($null -ne $media) { return [math]::Round([double]$media, 1) }
    } catch {  Write-Verbose $_.Exception.Message }

    return $null
}

Export-ModuleMember -Function Get-CpuRapido, Get-MemUsoMB, Get-DiscosInfo, Merge-DiscoFisico, Monitorar-Recursos, Diagnostico-Hardware, Get-CpuUsageRobusto
