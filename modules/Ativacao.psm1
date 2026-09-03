<#
    Ativacao.psm1 — ativacao e diagnostico conservador do WPA.
    Depende de Core.psm1. Nao remove chaves WPA. A funcao Ati e uma excecao
    remota preservada por solicitacao explicita do mantenedor.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking

$script:WpaRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\WPA'
$script:PsExec64DownloadUri = 'https://live.sysinternals.com/PsExec64.exe'
$script:PsExec64RequestedPath = 'C:\Softwares Instaladores\SysInternals\non_usage\PsExec64.exe'

function Get-WindowsDirectory {
    $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($windowsDirectory) -or
        -not (Test-Path -LiteralPath $windowsDirectory -PathType Container)) {
        throw 'Nao foi possivel localizar o diretorio do Windows.'
    }
    return $windowsDirectory
}

function Invoke-Slmgr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('/dlv','/ipk','/ato','/rilc')]
        [string]$Operation,

        [string]$ProductKey
    )

    if ($Operation -eq '/ipk') {
        if ($ProductKey -notmatch '^[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}$') {
            throw 'Chave invalida. Use 25 caracteres no formato XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.'
        }
    }
    elseif ($PSBoundParameters.ContainsKey('ProductKey')) {
        throw 'ProductKey so pode ser usado com /ipk.'
    }

    if ($Operation -ne '/dlv') { Require-Admin }

    $windowsDirectory = Get-WindowsDirectory
    $cscript = Join-Path $windowsDirectory 'System32\cscript.exe'
    $slmgr = Join-Path $windowsDirectory 'System32\slmgr.vbs'
    foreach ($requiredFile in @($cscript, $slmgr)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Arquivo nativo ausente: $requiredFile"
        }
    }

    $arguments = @('//nologo', ('"{0}"' -f $slmgr), $Operation)
    if ($Operation -eq '/ipk') { $arguments += $ProductKey.ToUpperInvariant() }

    $process = Start-Process -FilePath $cscript -ArgumentList $arguments -Wait -PassThru -NoNewWindow -ErrorAction Stop
    if ($process.ExitCode -ne 0) {
        throw "slmgr.vbs $Operation falhou com codigo $($process.ExitCode)."
    }
    Registrar-Log "slmgr.vbs $Operation concluido com codigo 0"
}

function Get-WpaWindows10 {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $version = $null
    if (-not [version]::TryParse([string]$os.Version, [ref]$version)) {
        throw "Versao do Windows invalida: '$($os.Version)'."
    }

    if (-not [Environment]::Is64BitOperatingSystem -or
        [int]$os.ProductType -ne 1 -or
        $version.Major -ne 10 -or
        [int]$os.BuildNumber -ge 22000) {
        throw 'O gerenciamento WPA inicial suporta somente Windows 10 desktop x64.'
    }
    return $os
}

function Get-WpaSample {
    if (-not (Test-Path -LiteralPath $script:WpaRegistryPath)) {
        throw 'A chave HKLM\SYSTEM\WPA nao foi encontrada.'
    }

    $readErrors = @()
    $subkeys = @(Get-ChildItem -LiteralPath $script:WpaRegistryPath -ErrorAction SilentlyContinue -ErrorVariable +readErrors)
    if ($readErrors.Count -gt 0) {
        throw "Nao foi possivel enumerar toda a chave WPA: $($readErrors[0].Exception.Message)"
    }

    $service = Get-Service -Name sppsvc -ErrorAction SilentlyContinue
    $process = Get-Process -Name sppsvc -ErrorAction SilentlyContinue | Select-Object -First 1
    [PSCustomObject]@{
        CapturedAt       = [DateTimeOffset]::Now
        SubkeyCount      = $subkeys.Count
        ServiceStatus    = if ($service) { [string]$service.Status } else { 'Nao encontrado' }
        ServiceStartType = if ($service) { [string]$service.StartType } else { $null }
        ProcessId        = if ($process) { [int]$process.Id } else { $null }
        CpuSeconds       = if ($process) { [double]$process.CPU } else { $null }
    }
}

function Get-WpaLicenseStatusText {
    param([int]$Status)
    switch ($Status) {
        0 { 'Sem licenca' }
        1 { 'Licenciado' }
        2 { 'Periodo OOB Grace' }
        3 { 'Periodo OOT Grace' }
        4 { 'Grace nao genuino' }
        5 { 'Notificacao' }
        6 { 'Grace estendido' }
        default { "Desconhecido ($Status)" }
    }
}

function Get-WpaDiagnostic {
    $os = Get-WpaWindows10
    $sample = Get-WpaSample

    $licenses = @()
    try {
        $licenses = @(Get-CimInstance -ClassName SoftwareLicensingProduct `
            -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    Name          = $_.Name
                    Channel       = $_.Description
                    LicenseStatus = Get-WpaLicenseStatusText -Status ([int]$_.LicenseStatus)
                    GraceMinutes  = [int]$_.GracePeriodRemaining
                }
            })
    }
    catch {
        Write-Warning "Nao foi possivel consultar SoftwareLicensingProduct: $($_.Exception.Message)"
    }

    $eventCount = $null
    try {
        $eventCount = @(Get-WinEvent -FilterHashtable @{
                LogName      = 'Application'
                ProviderName = 'Microsoft-Windows-Security-SPP'
                Level        = 1,2,3
                StartTime    = (Get-Date).AddDays(-7)
            } -MaxEvents 50 -ErrorAction Stop).Count
    }
    catch {
        Write-Verbose "Eventos Security-SPP indisponiveis: $($_.Exception.Message)"
    }

    [PSCustomObject]@{
        Windows          = $os.Caption
        Version          = $os.Version
        Build            = [int]$os.BuildNumber
        CapturedAt       = $sample.CapturedAt
        WpaSubkeyCount   = $sample.SubkeyCount
        SppsvcStatus     = $sample.ServiceStatus
        SppsvcStartType  = $sample.ServiceStartType
        SppsvcProcessId  = $sample.ProcessId
        SppsvcCpuSeconds = $sample.CpuSeconds
        SppErrors7Days   = $eventCount
        Licenses         = $licenses
    }
}

function Measure-WpaGrowth {
    [CmdletBinding()]
    param([ValidateRange(5,600)][int]$Seconds = 30)

    $null = Get-WpaWindows10
    $before = Get-WpaSample
    Start-Sleep -Seconds $Seconds
    $after = Get-WpaSample

    $cpuPercent = $null
    if ($before.ProcessId -and $before.ProcessId -eq $after.ProcessId -and
        $null -ne $before.CpuSeconds -and $null -ne $after.CpuSeconds) {
        $cpuDelta = [math]::Max(0, $after.CpuSeconds - $before.CpuSeconds)
        $cpuPercent = [math]::Round(($cpuDelta / ($Seconds * [Environment]::ProcessorCount)) * 100, 2)
    }

    [PSCustomObject]@{
        Seconds            = $Seconds
        InitialSubkeyCount = $before.SubkeyCount
        FinalSubkeyCount   = $after.SubkeyCount
        NewSubkeys         = $after.SubkeyCount - $before.SubkeyCount
        AverageCpuPercent  = $cpuPercent
        InitialStatus      = $before.ServiceStatus
        FinalStatus        = $after.ServiceStatus
    }
}

function Test-WpaPsExec64File {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        return (
            $item.VersionInfo.ProductName -eq 'Sysinternals PsExec' -and
            $signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid -and
            $signature.SignerCertificate.Subject -match '(?:^|, )(?:CN|O)=Microsoft Corporation(?:,|$)'
        )
    }
    catch { return $false }
}

function Find-WpaPsExec64 {
    $dataDirectory = Get-SyncMasterDataDir -SubPasta 'Tools\Sysinternals'
    $candidates = @(
        $env:SYNCMASTER_PSEXEC64
        $script:PsExec64RequestedPath
        (Join-Path $dataDirectory 'PsExec64.exe')
    )
    $candidates += @(Get-ChildItem -LiteralPath $dataDirectory -Filter 'PsExec64.exe' -File -Recurse `
        -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    foreach ($commandName in 'PsExec64.exe','psexec.exe') {
        $command = Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) { $candidates += $command.Source }
    }

    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-WpaPsExec64File -Path $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

function Install-WpaPsExec64 {
    [CmdletBinding()]
    param([switch]$AcceptLicense)

    $null = Get-WpaWindows10
    if (-not $AcceptLicense) {
        throw 'O download exige aceitacao explicita dos termos do Sysinternals.'
    }

    $directory = Get-SyncMasterDataDir -SubPasta 'Tools\Sysinternals'
    $destination = Join-Path $directory 'PsExec64.exe'
    if (Test-WpaPsExec64File -Path $destination) { return $destination }

    $winget = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($winget) {
        Write-Host 'Instalando o pacote exato Microsoft.Sysinternals.PsTools via WinGet...' -ForegroundColor Yellow
        $wingetArguments = @(
            'install', '--id', 'Microsoft.Sysinternals.PsTools', '--exact', '--source', 'winget',
            '--scope', 'user', '--location', ('"{0}"' -f $directory), '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
        )
        $wingetProcess = Start-Process -FilePath $winget.Source -ArgumentList $wingetArguments `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($wingetProcess.ExitCode -eq 0) {
            $installed = Find-WpaPsExec64
            if ($installed) {
                Registrar-Log 'PsTools instalado pelo pacote exato Microsoft.Sysinternals.PsTools e PsExec64 validado'
                return $installed
            }
            Write-Warning 'O WinGet concluiu, mas nenhum PsExec64 com assinatura Microsoft valida foi localizado.'
        }
        else {
            Write-Warning "WinGet falhou com codigo $($wingetProcess.ExitCode); tentando download direto da Microsoft."
        }
    }
    else {
        Write-Warning 'WinGet nao esta disponivel; usando o download direto da Microsoft.'
    }

    $temporary = Join-Path $directory ('.PsExec64-{0}.download' -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -Uri $script:PsExec64DownloadUri -OutFile $temporary -UseBasicParsing -ErrorAction Stop
        if (-not (Test-WpaPsExec64File -Path $temporary)) {
            throw 'O PsExec64 baixado nao possui produto e assinatura Microsoft validos.'
        }
        Move-Item -LiteralPath $temporary -Destination $destination -Force -ErrorAction Stop
        Registrar-Log 'PsExec64 obtido diretamente de live.sysinternals.com e validado'
        return $destination
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WpaSystemCount {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PsExecPath)

    $null = Get-WpaWindows10
    Require-Admin
    if (-not (Test-WpaPsExec64File -Path $PsExecPath)) {
        throw 'PsExec64 ausente ou sem assinatura Microsoft valida.'
    }

    $powershell = Join-Path (Get-WindowsDirectory) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
        throw "Windows PowerShell ausente: $powershell"
    }

    $command = "`$ErrorActionPreference='Stop'; @(Get-ChildItem -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\WPA' -ErrorAction Stop).Count"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $temporaryDirectory = Get-SyncMasterDataDir -SubPasta 'Temp'
    $token = [guid]::NewGuid().ToString('N')
    $standardOutput = Join-Path $temporaryDirectory ".wpa-system-$token.out"
    $standardError = Join-Path $temporaryDirectory ".wpa-system-$token.err"

    try {
        $arguments = @(
            '-accepteula', '-nobanner', '-s', ('"{0}"' -f $powershell),
            '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded
        )
        $process = Start-Process -FilePath $PsExecPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $standardOutput -RedirectStandardError $standardError -ErrorAction Stop
        if ($process.ExitCode -ne 0) {
            $detail = if (Test-Path -LiteralPath $standardError) {
                (Get-Content -LiteralPath $standardError -ErrorAction SilentlyContinue) -join ' '
            } else { '' }
            throw "PsExec64/consulta WPA falhou com codigo $($process.ExitCode). $detail"
        }

        $countLine = Get-Content -LiteralPath $standardOutput -ErrorAction Stop |
            Where-Object { $_.Trim() -match '^\d+$' } | Select-Object -Last 1
        $count = 0
        if ($null -eq $countLine -or -not [int]::TryParse($countLine.Trim(), [ref]$count)) {
            throw 'A consulta WPA como SYSTEM nao retornou uma contagem valida.'
        }
        Registrar-Log 'Consulta somente leitura de WPA como SYSTEM concluida'
        return $count
    }
    finally {
        Remove-Item -LiteralPath $standardOutput, $standardError -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WpaActivationRepair {
    $null = Get-WpaWindows10
    Require-Admin
    $service = Get-Service -Name sppsvc -ErrorAction Stop
    if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Restart-Service -Name sppsvc -Force -ErrorAction Stop
    }
    else {
        Start-Service -Name sppsvc -ErrorAction Stop
    }
    Invoke-Slmgr -Operation '/ato'
    Registrar-Log 'sppsvc reiniciado e tentativa oficial de ativacao concluida'
}

function Invoke-WpaLicenseFileRepair {
    $null = Get-WpaWindows10
    Require-Admin
    Invoke-Slmgr -Operation '/rilc'
    Registrar-Log 'Reinstalacao das licencas conhecidas concluida via slmgr /rilc'
}

function Menu-GerenciamentoWpa {
    try { $null = Get-WpaWindows10 }
    catch {
        Write-Warning $_.Exception.Message
        Pause-Script
        return
    }

    do {
        Clear-Host
        Write-Host '--- WPA / PROTECAO DE SOFTWARE (WINDOWS 10 x64) ---' -ForegroundColor Cyan
        Write-Host '1 - Diagnosticar licenca, sppsvc, eventos e quantidade de subchaves (somente leitura)'
        Write-Host '2 - Medir crescimento das subchaves WPA por um intervalo (somente leitura)'
        Write-Host '3 - Contar subchaves como SYSTEM com PsExec64 validado (somente leitura)'
        Write-Host '4 - Reiniciar o sppsvc e tentar ativacao oficial (/ato)'
        Write-Host '5 - Reinstalar licencas conhecidas (/rilc; nao apaga WPA)'
        Write-Host '6 - Abrir a pagina oficial de Ativacao/Solucao de Problemas'
        Write-Host 'Q - Voltar'
        Write-Warning 'A quantidade isolada nao define saude. O Sync Master nunca apaga HKLM\SYSTEM\WPA.'
        $choice = Read-Host 'Sua escolha'

        try {
            switch ($choice.ToUpper()) {
                '1' {
                    $diagnostic = Get-WpaDiagnostic
                    $diagnostic | Select-Object Windows,Version,Build,CapturedAt,WpaSubkeyCount,
                        SppsvcStatus,SppsvcStartType,SppsvcProcessId,SppsvcCpuSeconds,SppErrors7Days | Format-List
                    if ($diagnostic.Licenses.Count -gt 0) {
                        Write-Host 'Licencas Windows detectadas:' -ForegroundColor Cyan
                        $diagnostic.Licenses | Format-Table -AutoSize
                    }
                    Pause-Script
                }
                '2' {
                    $rawSeconds = Read-Host 'Intervalo em segundos (5-600; Enter = 30)'
                    $seconds = 30
                    if ($rawSeconds -and
                        (-not [int]::TryParse($rawSeconds, [ref]$seconds) -or $seconds -lt 5 -or $seconds -gt 600)) {
                        Write-Warning 'Intervalo invalido.'
                        Pause-Script
                        continue
                    }
                    Write-Host "Observando WPA por $seconds segundo(s)..." -ForegroundColor Yellow
                    $growth = Measure-WpaGrowth -Seconds $seconds
                    $growth | Format-List
                    if ($growth.NewSubkeys -gt 0) {
                        Write-Warning "Foram criadas $($growth.NewSubkeys) subchave(s) no intervalo. Correlacione com licenca, CPU e eventos."
                    }
                    else {
                        Write-Host 'Nenhum crescimento foi observado nesse intervalo.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '3' {
                    Write-Host 'Termos: https://learn.microsoft.com/sysinternals/license-terms' -ForegroundColor Cyan
                    if (-not (Confirm-Action 'Executar consulta fixa e somente leitura como SYSTEM, aceitando os termos do PsExec?')) {
                        Write-Host 'Cancelado.' -ForegroundColor DarkGray
                        Pause-Script
                        continue
                    }
                    $psExec = Find-WpaPsExec64
                    if (-not $psExec) {
                        Write-Host 'PsExec64 nao encontrado. Ele nao pode ser redistribuido dentro do Sync Master.' -ForegroundColor Yellow
                        if (-not (Confirm-Action 'Instalar o PsTools pelo WinGet (ou baixar da Microsoft como fallback) e validar o PsExec64?')) {
                            Write-Host 'Cancelado.' -ForegroundColor DarkGray
                            Pause-Script
                            continue
                        }
                        $psExec = Install-WpaPsExec64 -AcceptLicense
                    }
                    $systemCount = Invoke-WpaSystemCount -PsExecPath $psExec
                    Write-Host "Subchaves WPA visiveis como SYSTEM: $systemCount" -ForegroundColor Cyan
                    Pause-Script
                }
                '4' {
                    if (Confirm-Action 'Reiniciar graciosamente o sppsvc e executar slmgr.vbs /ato?') {
                        Invoke-WpaActivationRepair
                        Write-Host 'Servico reiniciado e tentativa de ativacao concluida.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '5' {
                    Write-Warning '/rilc reinstala licencas conhecidas; nao promete limpar ou reconstruir HKLM\SYSTEM\WPA.'
                    if (Confirm-Action 'Executar o reparo oficial slmgr.vbs /rilc?') {
                        Invoke-WpaLicenseFileRepair
                        Write-Host 'Reinstalacao de licencas concluida.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '6' {
                    Start-Process 'ms-settings:activation' -ErrorAction Stop
                    Pause-Script
                }
                'Q' { return }
                default { Write-Warning 'Opcao invalida.'; Pause-Script }
            }
        }
        catch {
            Write-Warning "A operacao WPA falhou: $($_.Exception.Message)"
            Registrar-Log "ERRO WPA: $($_.Exception.Message)"
            Pause-Script
        }
    } while ($true)
}

function Menu-Ativacao {
    do {
        Clear-Host; Write-Host '--- GERENCIAMENTO DE ATIVACAO (FERRAMENTAS OFICIAIS) ---' -ForegroundColor Cyan
        Write-Host '1 - Mostrar Status Detalhado da Ativacao'
        Write-Host '2 - Instalar uma Chave de Produto (Product Key)'
        Write-Host '3 - Tentar Ativacao Online'
        Write-Host 'Q - Voltar ao Menu Principal'
        $choice = Read-Host 'Sua escolha'
        switch ($choice.ToUpper()) {
            '1' { Mostrar-StatusAtivacao }
            '2' { Instalar-ChaveProduto }
            '3' { Ativar-Windows }
            '4' { Ati }
            'Q' { return }
            default { Write-Warning 'Opcao invalida.' }
        }
    } while ($true)
}

function Mostrar-StatusAtivacao {
    try {
        Write-Host 'Exibindo informacoes detalhadas de licenciamento...' -ForegroundColor Yellow
        Invoke-Slmgr -Operation '/dlv'
    }
    catch { Write-Warning $_.Exception.Message }
    Pause-Script
}

function Instalar-ChaveProduto {
    [CmdletBinding()]
    param([string]$ProductKey)

    $bstr = [IntPtr]::Zero
    try {
        if ([string]::IsNullOrWhiteSpace($ProductKey)) {
            $secureKey = Read-Host -Prompt 'Insira a chave legitima (a digitacao ficara oculta)' -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
            $ProductKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        if ($ProductKey -notmatch '^[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}$') {
            throw 'Chave invalida. Use o formato XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.'
        }
        Write-Host 'Instalando a chave de produto...' -ForegroundColor Yellow
        Invoke-Slmgr -Operation '/ipk' -ProductKey $ProductKey.ToUpperInvariant()
        Write-Host 'Chave instalada.' -ForegroundColor Green
    }
    catch { Write-Warning $_.Exception.Message }
    finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $ProductKey = $null
    }
    Pause-Script
}

function Ati {
    # Endurecimento (supply-chain): baixa->SHA256->confirma, com pin opcional, e
    # executa via scriptblock (em vez de Invoke-Expression).
    param(
        [string]$Url = 'https://get.activated.win',
        [string]$ExpectedSha256 = $env:MAS_EXPECTED_SHA256
    )
    Write-Host "ATENCAO: isto baixa e EXECUTA um script remoto de $Url (Microsoft Activation Scripts)." -ForegroundColor Yellow
    Write-Host 'Executar codigo remoto sem inspecionar e um risco de seguranca.' -ForegroundColor Yellow

    try {
        $script = Invoke-RestMethod -Uri $Url -ErrorAction Stop
    }
    catch {
        Write-Warning "Falha ao baixar o ativador. Verifique a conexao/antivirus: $($_.Exception.Message)"
        Pause-Script
        return
    }
    if ([string]::IsNullOrWhiteSpace($script)) {
        Write-Warning 'Conteudo baixado vazio. Abortando.'
        Pause-Script
        return
    }

    $bytes = [Text.Encoding]::UTF8.GetBytes($script)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    Write-Host ("Tamanho: {0:N0} bytes | SHA256: {1}" -f $bytes.Length, $hash) -ForegroundColor Cyan

    if ($ExpectedSha256) {
        if ($hash -ne $ExpectedSha256.Trim().ToLowerInvariant()) {
            Write-Warning "SHA256 NAO corresponde ao esperado ($ExpectedSha256). ABORTANDO por seguranca."
            Pause-Script
            return
        }
        Write-Host 'SHA256 confere com o esperado.' -ForegroundColor Green
    }

    if (-not (Confirm-Action -Prompt 'Executar o ativador com o SHA256 acima?')) {
        Write-Host 'Cancelado.' -ForegroundColor DarkGray
        Pause-Script
        return
    }
    try {
        Registrar-Log "Ativar-Crack: executando MAS de $Url (sha256=$hash)"
        & ([scriptblock]::Create($script))
    }
    catch {
        Write-Warning "Falha ao executar o ativador: $($_.Exception.Message)"
    }
    Pause-Script
}

function Ativar-Windows {
    try {
        Write-Host 'Tentando ativar o Windows conforme o canal instalado...' -ForegroundColor Yellow
        Invoke-Slmgr -Operation '/ato'
        Write-Host 'Tentativa de ativacao concluida.' -ForegroundColor Green
    }
    catch { Write-Warning $_.Exception.Message }
    Pause-Script
}

Export-ModuleMember -Function Menu-Ativacao, Mostrar-StatusAtivacao, Instalar-ChaveProduto, Ativar-Windows, Menu-GerenciamentoWpa
