# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L31    Pause-Local
#   L36    Is-ServerOS
#   L42    Set-DWord
#   L52    Backup-Registro
#   L78    Show-Estado
#   L94    Toggle-PowerPlan
#   L108   Clean-Temp
#   L129   STARTUPS (com seleção por números) =================================
#   L147   Get-Startups
#   L245   Parse-Selection
#   L286   Disable-StartupByNumber
#   L338   Enable-StartupByNumber
#   L389   Menu-Startups
#   L433   Storage-Maintenance
#   L478   Disk-SMART
#   L494   Power-CPU-Tune
#   L531   SearchIndexer-Toggle
#   L547   Tasks-Noise
# ======================= END NAV INDEX =======================

<#
    Otimizacao.psm1 — funcoes de otimizacao/desempenho avancado extraidas do
    launcher Sync_Master.ps1 (Fase 2 do refator). Antes viviam ANINHADAS dentro de
    Menu-OtimizacaoAvancada (escopo fragil: so existiam quando aquele menu rodava).
    Depende de Core.psm1 (Pause-Script, Confirm-Action, Require-Admin, Ensure-Dir).
#>

# Wrapper retrocompativel: o codigo legado chama Pause-Local; delega ao Pause-Script do Core.
function Pause-Local { Pause-Script }
    # ===================== UTILITÁRIOS INTERNOS ======================
    
    
    
    function Is-ServerOS {
        # Win32_OperatingSystem.ProductType: 1=Workstation, 2=Domain Controller, 3=Server.
        # Via CIM é instantâneo; Get-ComputerInfo (versão antiga) levava segundos.
        try { ([int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType) -ne 1 }
        catch { $false }
    }
    function Set-DWord($Path,$Name,$Value){
        # Auto-backup do Registro UMA vez por sessão antes da 1ª escrita destrutiva.
        if (-not $script:RegBackupDone) {
            try { Backup-Registro; $script:RegBackupDone = $true }
            catch { Write-Warning "Backup automático do Registro falhou: $($_.Exception.Message)" }
        }
        New-Item -Path $Path -Force | Out-Null
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
        Registrar-Log ("Set-DWord {0}\{1} = {2}" -f $Path, $Name, $Value)
    }
    function Backup-Registro {
        Require-Admin
        $date = Get-Date -Format "yyyyMMdd_HHmmss"
        $dir  = Join-Path $env:USERPROFILE "Desktop\RegBackup_$date"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        # reg.exe e nativo: exit != 0 NAO lanca, entao checamos $LASTEXITCODE por chave.
        # Algumas chaves (ex.: policy DataCollection) podem nem existir num host nao gerenciado;
        # acumulamos as falhas e avisamos em vez de fingir backup completo (Set-DWord confia nisto).
        $exports = @(
            @{Key='HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; File='MemoryManagement.reg'},
            @{Key='HKLM\SYSTEM\CurrentControlSet\Control\Power';                              File='Power.reg'},
            @{Key='HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl';                    File='PriorityControl.reg'},
            @{Key='HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection';                  File='DataCollection.reg'},
            @{Key='HKCU\Control Panel\Desktop';                                               File='Desktop.reg'}
        )
        $falhas = @()
        foreach ($e in $exports) {
            reg export $e.Key (Join-Path $dir $e.File) /y | Out-Null
            if ($LASTEXITCODE -ne 0) { $falhas += $e.Key }
        }
        if ($falhas.Count) {
            Write-Warning ("reg export falhou em {0} chave(s) (pode nao existir neste host): {1}" -f $falhas.Count, ($falhas -join '; '))
        }
        Write-Host ("Backup salvo em: {0}" -f $dir) -ForegroundColor Cyan
        Registrar-Log ("Backup-Registro -> {0} (falhas: {1})" -f $dir, $falhas.Count)
    }
    function Show-Estado {
        $mmPath   = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        $powPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
        $prioPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        $telPath  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        $estado = [pscustomobject]@{
            OS_Tipo                 = if (Is-ServerOS) { 'Server' } else { 'Client' }
            DisablePagingExecutive  = (Get-ItemProperty -Path $mmPath -Name DisablePagingExecutive -ErrorAction SilentlyContinue).DisablePagingExecutive
            LargeSystemCache        = (Get-ItemProperty -Path $mmPath -Name LargeSystemCache      -ErrorAction SilentlyContinue).LargeSystemCache
            HibernateEnabled        = (Get-ItemProperty -Path $powPath -Name HibernateEnabled      -ErrorAction SilentlyContinue).HibernateEnabled
            Win32PrioritySeparation = (Get-ItemProperty -Path $prioPath -Name Win32PrioritySeparation -ErrorAction SilentlyContinue).Win32PrioritySeparation
            AllowTelemetry          = (Get-ItemProperty -Path $telPath -Name AllowTelemetry        -ErrorAction SilentlyContinue).AllowTelemetry
            PlanoDeEnergia          = ((powercfg /getactivescheme) 2>$null)
        }
        $estado | Format-List
    }
    function Toggle-PowerPlan {
        try {
            $isLaptop = (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
            if ($isLaptop) {
                powercfg -setactive SCHEME_BALANCED | Out-Null
                Write-Host "Plano de energia: Equilibrado (notebook detectado)." -ForegroundColor Yellow
            } else {
                powercfg -setactive SCHEME_MIN | Out-Null
                Write-Host "Plano de energia: Alto desempenho (desktop)." -ForegroundColor Green
            }
        } catch {
            Write-Warning ("Falha ao ajustar plano: {0}" -f $_.Exception.Message)
        }
    }
    function Clean-Temp {
        Require-Admin
        $paths = @("$env:TEMP\*", "$env:WINDIR\Temp\*")
        foreach ($p in $paths) {
            try { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
        }
        try {
            # Dism.exe e nativo: exit != 0 NAO lanca. O catch so pega Dism.exe ausente;
            # o resultado real vem do $LASTEXITCODE (senao "concluida" mentia em falha).
            Dism.exe /Online /Cleanup-Image /StartComponentCleanup | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Limpeza concluída (TEMP e Component Store)." -ForegroundColor Green
            } else {
                Write-Warning ("DISM retornou código {0} — Component Store NÃO limpo (TEMP já foi limpo)." -f $LASTEXITCODE)
            }
        } catch {
            Write-Warning ("DISM falhou: {0}" -f $_.Exception.Message)
        }
        Registrar-Log "Clean-Temp executado (TEMP + Component Store)"
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
    $items | Sort-Object Enabled, Name
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


    # ---------- ARMAZENAMENTO: TRIM / DEFRAG ----------
    function Storage-Maintenance {
        Clear-Host
        Write-Host "--- Manutenção de Armazenamento ---" -ForegroundColor Cyan
        try {
            Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } |
                Format-Table DriveLetter, FileSystemLabel, FileSystem, @{N='Livre(GB)';E={[math]::Round($_.SizeRemaining/1GB,1)}}, @{N='Tamanho(GB)';E={[math]::Round($_.Size/1GB,1)}} -AutoSize
        } catch { Write-Verbose $_.Exception.Message }
        Write-Host "`n1) ReTRIM em SSDs  2) Desfragmentar HDDs  3) Verificar TRIM  4) Voltar"
        $c = Read-Host "Escolha"
        switch ($c) {
            '1' {
                Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object {
                    try {
                        # Detecta mídia
                        $part = Get-Partition -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue | Select-Object -First 1
                        $disk = if ($part) { Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue }
                        if ($disk -and $disk.MediaType -eq 'SSD') {
                            Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -Verbose
                        }
                    } catch { Write-Verbose $_.Exception.Message }
                }
                Pause-Local
            }
            '2' {
                Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object {
                    try {
                        $part = Get-Partition -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue | Select-Object -First 1
                        $disk = if ($part) { Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue }
                        if ($disk -and $disk.MediaType -eq 'HDD') {
                            Optimize-Volume -DriveLetter $_.DriveLetter -Defrag -Verbose
                        }
                    } catch { Write-Verbose $_.Exception.Message }
                }
                Pause-Local
            }
            '3' {
                fsutil behavior query DisableDeleteNotify
                Write-Host "Se o resultado é 0, o TRIM está habilitado." -ForegroundColor Yellow
                Pause-Local
            }
            default { return }
        }
    }

    # ---------- SMART (básico) ----------
    function Disk-SMART {
        Clear-Host
        Write-Host "--- SMART (Básico) ---" -ForegroundColor Cyan
        try {
            $st = Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop
            foreach ($s in $st) {
                $ok = -not $s.PredictFailure
                Write-Host ("{0}`n  FalhaPrevista: {1}" -f $s.InstanceName, $(if($ok){"não"}else{"SIM"})) -ForegroundColor $(if($ok){'Green'}else{'Red'})
            }
        } catch {
            Write-Warning "SMART WMI indisponível neste host/driver. Considere a ferramenta do fabricante do disco."
        }
        Pause-Local
    }

    # ---------- Energia / CPU ----------
    function Power-CPU-Tune {
        Clear-Host
        Write-Host "--- Energia/CPU ---" -ForegroundColor Cyan
        Write-Host "1) Aplicar plano recomendado (Desktop: Alto desempenho; Notebook: Equilibrado)"
        Write-Host "2) Desktop: fixar min/max do processador em 100% (cuidado em notebooks)"
        Write-Host "3) Restaurar plano Equilibrado"
        Write-Host "4) Voltar"
        $c = Read-Host "Escolha"
        switch ($c) {
            '1' {
                Toggle-PowerPlan
                Pause-Local
            }
            '2' {
                Require-Admin
                try {
                    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
                    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
                    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
                    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
                    powercfg -setactive SCHEME_CURRENT
                    Write-Host "Processador fixado em 100% (pode aumentar consumo/temperatura)." -ForegroundColor Yellow
                } catch {
                    Write-Warning ("Falha ao aplicar: {0}" -f $_.Exception.Message)
                }
                Pause-Local
            }
            '3' {
                powercfg -setactive SCHEME_BALANCED | Out-Null
                Write-Host "Plano Equilibrado restaurado." -ForegroundColor Green
                Pause-Local
            }
            default { return }
        }
    }

    # ---------- Indexador de Pesquisa ----------
    function SearchIndexer-Toggle {
        Clear-Host
        Write-Host "--- Indexador de Pesquisa (WSearch) ---" -ForegroundColor Cyan
        $svc = Get-Service WSearch -ErrorAction SilentlyContinue
        if (-not $svc) { Write-Warning "Serviço WSearch não encontrado."; Pause-Local; return }
        Write-Host ("Estado atual: {0}" -f $svc.Status)
        Write-Host "1) Pausar (Stop-Service)   2) Retomar (Start-Service)   3) Voltar"
        $c = Read-Host "Escolha"
        switch ($c) {
            '1' { Stop-Service WSearch -Force; Write-Host "Indexador pausado." -ForegroundColor Yellow; Pause-Local }
            '2' { Start-Service WSearch;        Write-Host "Indexador retomado." -ForegroundColor Green;  Pause-Local }
            default { return }
        }
    }

    # ---------- Tarefas agendadas ruidosas ----------
    function Tasks-Noise {
        Clear-Host
        Write-Host "--- Tarefas Agendadas (Updaters/Telemetry) ---" -ForegroundColor Cyan
        $cands = @(
            '\Microsoft\Office\',
            '\Microsoft\Windows\UpdateOrchestrator\',
            '\Microsoft\Windows\Application Experience\',
            '\Microsoft\Windows\Customer Experience Improvement Program\',
            '\Adobe\','\Google\Update\','\Microsoft\EdgeUpdate\','\Teams\','\OneDrive\'
        )
        $tasks = @()
        foreach ($path in $cands) {
            try { $tasks += Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
        }
        if (-not $tasks) { Write-Host "Nenhuma tarefa localizada nos caminhos monitorados." -ForegroundColor Yellow; Pause-Local; return }
        $tasks = $tasks | Sort-Object TaskPath, TaskName
        $i=0; $map=@{}
        foreach ($t in $tasks) { $i++; $map[$i]=$t; Write-Host ("{0,3}. [{1}] {2}{3}" -f $i, $t.State, $t.TaskPath, $t.TaskName) }
        Write-Host "A) Desabilitar por número   B) Habilitar por número   Q) Voltar"
        $ans = Read-Host "Escolha"
        switch ($ans.ToUpper()) {
            'A' { $ns = Read-Host "Número"; if ($ns -match '^\d+$' -and $map[[int]$ns]) { Disable-ScheduledTask -InputObject $map[[int]$ns] | Out-Null; Write-Host "Desabilitada." -ForegroundColor Yellow } else { Write-Warning "Número inválido." }; Pause-Local }
            'B' { $ns = Read-Host "Número"; if ($ns -match '^\d+$' -and $map[[int]$ns]) { Enable-ScheduledTask  -InputObject $map[[int]$ns] | Out-Null; Write-Host "Habilitada."  -ForegroundColor Green  } else { Write-Warning "Número inválido." }; Pause-Local }
            default { return }
        }
    }

# Aliases de verbo aprovado (retrocompat): chamada por nome PT segue funcionando;
# os aliases melhoram a descoberta no console (Get-Command Clear-*, Switch-*).
Set-Alias -Name Clear-Temp       -Value Clean-Temp     -Scope Script -Force
Set-Alias -Name Switch-PowerPlan -Value Toggle-PowerPlan -Scope Script -Force

Export-ModuleMember -Function Pause-Local, Is-ServerOS, Set-DWord, Backup-Registro, `
    Show-Estado, Toggle-PowerPlan, Clean-Temp, Get-Startups, Parse-Selection, `
    Disable-StartupByNumber, Enable-StartupByNumber, Menu-Startups, `
    Storage-Maintenance, Disk-SMART, Power-CPU-Tune, SearchIndexer-Toggle, Tasks-Noise `
    -Alias Clear-Temp, Switch-PowerPlan
