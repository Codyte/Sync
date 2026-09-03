# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L55    Get-WindowsDirectory
#   L64    Invoke-Slmgr
#   L132   Get-WpaSupportedWindows
#   L149   Get-WpaSample
#   L173   Get-WpaLicenseStatusText
#   L187   Get-WpaDiagnostic
#   L244   Measure-WpaGrowth
#   L275   Get-WpaHiveSize
#   L292   Get-WpaAclSample
#   L344   Test-WpaActivatorFootprint
#   L408   Test-WpaPsExec64File
#   L423   Find-WpaPsExec64
#   L444   Install-WpaPsExec64
#   L501   Invoke-WpaSystemProbe
#   L608   Invoke-WpaActivationRepair
#   L622   Invoke-WpaLicenseFileRepair
#   L634   Get-WpaActivationState
#   L655   Get-WpaLicenseDetail
#   L666   Invoke-WpaLicensingDiag
#   L687   Export-WpaReport
#   L714   Backup-WpaRegistry
#   L738   Repair-WpaServices
#   L777   Clear-WpaKmsConfig
#   L786   Reset-WpaTokens
#   L833   Repair-WpaSystemFiles
#   L856   Uninstall-WpaProductKey
#   L866   Invoke-WpaRearm
#   L875   Invoke-WpaPhoneActivation
#   L902   Invoke-WpaGuidedRepair
#   L952   Get-WpaReactivationRisk
#   L1019  Invoke-WpaOfflineResetGuide
#   L1115  Invoke-WpaTriage
#   L1227  Menu-GerenciamentoWpa
#   L1461  Menu-Ativacao
#   L1480  Mostrar-StatusAtivacao
#   L1489  Instalar-ChaveProduto
#   L1515  Ati
#   L1569  Ativar-Windows
# ======================= END NAV INDEX =======================

<#
    Ativacao.psm1 — ativacao e diagnostico conservador do WPA.
    Depende de Core.psm1. Nao remove chaves WPA. A funcao Ati e uma excecao
    remota preservada por solicitacao explicita do mantenedor.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking

$script:WpaRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\WPA'
$script:WpaHiveSubPath = 'SYSTEM\WPA'
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
        [ValidateSet('/dlv','/dli','/xpr','/dti','/ipk','/ato','/atp','/rilc','/ckms','/upk','/cpky','/rearm')]
        [string]$Operation,

        [string]$ProductKey,

        # Somente /atp: ID de confirmacao de 48 digitos dado pela central.
        [string]$ConfirmationId,

        # Devolve a saida em vez de imprimir. Usado pelos relatorios.
        [switch]$Quiet
    )

    if ($Operation -eq '/ipk') {
        if ($ProductKey -notmatch '^[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}$') {
            throw 'Chave invalida. Use 25 caracteres no formato XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.'
        }
    }
    elseif ($PSBoundParameters.ContainsKey('ProductKey')) {
        throw 'ProductKey so pode ser usado com /ipk.'
    }

    if ($Operation -eq '/atp') {
        $digits = ($ConfirmationId -replace '[\s-]', '')
        if ($digits -notmatch '^\d{48}$') {
            throw 'ID de confirmacao invalido. A central fornece 48 digitos.'
        }
        $ConfirmationId = $digits
    }
    elseif ($PSBoundParameters.ContainsKey('ConfirmationId')) {
        throw 'ConfirmationId so pode ser usado com /atp.'
    }

    if ($Operation -notin @('/dlv','/dli','/xpr')) { Require-Admin }

    $windowsDirectory = Get-WindowsDirectory
    $cscript = Join-Path $windowsDirectory 'System32\cscript.exe'
    $slmgr = Join-Path $windowsDirectory 'System32\slmgr.vbs'
    foreach ($requiredFile in @($cscript, $slmgr)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Arquivo nativo ausente: $requiredFile"
        }
    }

    $arguments = @('//nologo', $slmgr, $Operation)
    if ($Operation -eq '/ipk') { $arguments += $ProductKey.ToUpperInvariant() }
    if ($Operation -eq '/atp') { $arguments += $ConfirmationId }

    $previousEncoding = [Console]::OutputEncoding
    try {
        # cscript escreve no code page OEM; sem isso o relatorio sai com acentos quebrados.
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(
            [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $output = & $cscript @arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { [Console]::OutputEncoding = $previousEncoding }
    if ($exitCode -ne 0) {
        throw "slmgr.vbs $Operation falhou com codigo $exitCode. $(($output | Select-Object -Last 3) -join ' ')"
    }
    Registrar-Log "slmgr.vbs $Operation concluido com codigo 0"
    if ($Quiet) { return $output }
    $output | Out-Host
}

function Get-WpaSupportedWindows {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $version = $null
    if (-not [version]::TryParse([string]$os.Version, [ref]$version)) {
        throw "Versao do Windows invalida: '$($os.Version)'."
    }

    # Windows 11 se reporta como 10.0.22000+; o licenciamento (sppsvc, slmgr,
    # tokens.dat) e identico ao do Windows 10. Server e 32 bits ficam de fora.
    if (-not [Environment]::Is64BitOperatingSystem -or
        [int]$os.ProductType -ne 1 -or
        $version.Major -ne 10) {
        throw 'O gerenciamento WPA suporta somente Windows 10/11 desktop x64.'
    }
    return $os
}

function Get-WpaSample {
    <#
      SubKeyCount sai do proprio hive: e instantaneo e nao depende da ACL de cada
      subchave. Enumerar com Get-ChildItem levava minutos numa arvore inchada, e
      era esse atraso que inflava a janela real de Measure-WpaGrowth -- o objeto
      dizia 300 segundos enquanto a medicao tinha durado onze minutos.
    #>
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:WpaHiveSubPath)
    if (-not $key) { throw 'A chave HKLM\SYSTEM\WPA nao foi encontrada.' }
    try { $subkeyCount = [int]$key.SubKeyCount }
    finally { $key.Dispose() }

    $service = Get-Service -Name sppsvc -ErrorAction SilentlyContinue
    $process = Get-Process -Name sppsvc -ErrorAction SilentlyContinue | Select-Object -First 1
    [PSCustomObject]@{
        CapturedAt       = [DateTimeOffset]::Now
        SubkeyCount      = $subkeyCount
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
    $os = Get-WpaSupportedWindows
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

    # Sinal barato e independente da contagem: o hive inchado aparece em disco
    # mesmo quando a arvore nao da para enumerar. Sem elevacao, o arquivo nao e
    # nem listavel, e ai o campo fica nulo em vez de derrubar o diagnostico.
    $hiveMegaBytes = $null
    try { $hiveMegaBytes = (Get-WpaHiveSize).MegaBytes }
    catch { Write-Verbose "Tamanho do hive SYSTEM indisponivel: $($_.Exception.Message)" }

    [PSCustomObject]@{
        Windows          = $os.Caption
        Version          = $os.Version
        Build            = [int]$os.BuildNumber
        CapturedAt       = $sample.CapturedAt
        WpaSubkeyCount   = $sample.SubkeyCount
        HiveMegaBytes    = $hiveMegaBytes
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

    $null = Get-WpaSupportedWindows
    $before = Get-WpaSample
    Start-Sleep -Seconds $Seconds
    $after = Get-WpaSample

    # A janela real, nao a pedida: quem divide o delta de CPU pelo intervalo
    # solicitado inventa um percentual quando a coleta demora mais que o sleep.
    $elapsed = [math]::Round(($after.CapturedAt - $before.CapturedAt).TotalSeconds, 1)

    $cpuPercent = $null
    if ($before.ProcessId -and $before.ProcessId -eq $after.ProcessId -and
        $null -ne $before.CpuSeconds -and $null -ne $after.CpuSeconds -and $elapsed -gt 0) {
        $cpuDelta = [math]::Max(0, $after.CpuSeconds - $before.CpuSeconds)
        $cpuPercent = [math]::Round(($cpuDelta / ($elapsed * [Environment]::ProcessorCount)) * 100, 2)
    }

    [PSCustomObject]@{
        Seconds            = $elapsed
        InitialSubkeyCount = $before.SubkeyCount
        FinalSubkeyCount   = $after.SubkeyCount
        NewSubkeys         = $after.SubkeyCount - $before.SubkeyCount
        AverageCpuPercent  = $cpuPercent
        InitialStatus      = $before.ServiceStatus
        FinalStatus        = $after.ServiceStatus
    }
}

function Get-WpaHiveSize {
    <#
      O arquivo do hive SYSTEM inteiro, em disco. E o sinal mais barato que
      existe: normal fica entre 10 e 30 MB, e centenas de MB confirmam o inchaco
      sem enumerar uma subchave sequer. O kernel mantem o arquivo aberto, entao
      so o tamanho e legivel daqui -- nunca o conteudo.
    #>
    $file = Join-Path (Get-WindowsDirectory) 'System32\config\SYSTEM'
    $item = Get-Item -LiteralPath $file -Force -ErrorAction Stop
    [PSCustomObject]@{
        Path      = $file
        Bytes     = [long]$item.Length
        MegaBytes = [math]::Round($item.Length / 1MB, 1)
        Inchado   = ([long]$item.Length -gt 100MB)
    }
}

function Get-WpaAclSample {
    <#
      Perfis de ACL da arvore WPA por amostragem. Get-Acl custa uma chamada por
      subchave: em centenas de milhares de chaves sao horas de espera, e a
      pergunta -- de quantos perfis distintos a arvore e feita, e quantos deles o
      chamador nao consegue ler -- ja se responde numa amostra.
    #>
    [CmdletBinding()]
    param([ValidateRange(20,5000)][int]$Limit = 400)

    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:WpaHiveSubPath)
    if (-not $key) { throw 'A chave HKLM\SYSTEM\WPA nao foi encontrada.' }
    try {
        $total = [int]$key.SubKeyCount
        $names = @($key.GetSubKeyNames())
    }
    finally { $key.Dispose() }

    # Passo fixo em vez das primeiras N: a arvore inchada cresce no fim, e ler so
    # o comeco devolveria sempre o mesmo perfil antigo.
    $sample = $names
    if ($names.Count -gt $Limit) {
        $step = [int][math]::Ceiling($names.Count / $Limit)
        $sample = @(for ($i = 0; $i -lt $names.Count; $i += $step) { $names[$i] })
    }

    $groups = @{}
    $unreadable = 0
    foreach ($name in $sample) {
        $sddl = '<ILEGIVEL>'
        try { $sddl = (Get-Acl -LiteralPath "$script:WpaRegistryPath\$name" -ErrorAction Stop).Sddl }
        catch { $unreadable++ }
        if ($groups.ContainsKey($sddl)) { $groups[$sddl]++ } else { $groups[$sddl] = 1 }
    }

    $owner = '<ILEGIVEL>'
    try { $owner = (Get-Acl -LiteralPath $script:WpaRegistryPath -ErrorAction Stop).Owner }
    catch { Write-Verbose "Dono da raiz WPA ilegivel: $($_.Exception.Message)" }

    [PSCustomObject]@{
        Count       = $total
        Listed      = $names.Count
        Sampled     = @($sample).Count
        Unreadable  = $unreadable
        RootOwner   = $owner
        AclProfiles = $groups.Keys.Count
        AclGroups   = @($groups.GetEnumerator() | ForEach-Object {
                [PSCustomObject]@{ Subkeys = $_.Value; Sddl = $_.Key }
            })
    }
}

function Test-WpaActivatorFootprint {
    <#
      A bifurcacao que decide todo o resto: com um ativador vivo na maquina,
      reparar e tratar sintoma -- ele desfaz o reparo na proxima renovacao. Tres
      sinais independentes, nenhum conclusivo sozinho, e por isso a evidencia sai
      como texto para o operador ler, nao como sentenca.
    #>
    $null = Get-WpaSupportedWindows
    $evidence = [System.Collections.Generic.List[string]]::new()

    $oemKey = $null
    $kmsMachine = $null
    $limitado = -not (Test-IsAdmin)
    try {
        $licensingService = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
        $oemKey = [string]$licensingService.OA3xOriginalProductKey
        $kmsMachine = [string]$licensingService.KeyManagementServiceMachine
    }
    catch {
        Write-Verbose "SoftwareLicensingService indisponivel: $($_.Exception.Message)"
        $limitado = $true
    }

    $kmsChannel = @(Get-CimInstance -ClassName SoftwareLicensingProduct `
            -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.Description -match 'KMSCLIENT' })

    # Canal KMS numa maquina com chave OEM gravada no firmware nao se explica
    # sozinho: ali o normal e OEM_DM ou Retail. Num dominio com KMS de verdade
    # isso e legitimo, entao vale como indicio, nunca como prova.
    if ($kmsChannel.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($oemKey)) {
        $evidence.Add("Canal KMSCLIENT em maquina com chave OEM no firmware ($($kmsChannel.Count) produto(s)).")
    }
    if (-not [string]::IsNullOrWhiteSpace($kmsMachine)) {
        $evidence.Add("Servidor KMS fixado na maquina: $kmsMachine")
    }

    # Tarefas sob \Microsoft\ ficam de fora: o proprio Windows agenda renovacao
    # de licenca ali, e incluir esse ramo faria todo mundo parecer infectado.
    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
                $_.TaskPath -notlike '\Microsoft\*' -and $_.TaskName -match '(?i)KMS|activat|ativa|renew'
            })
    }
    catch { Write-Verbose "Tarefas agendadas indisponiveis: $($_.Exception.Message)" }
    foreach ($task in $tasks) {
        $evidence.Add("Tarefa agendada com cara de renovador: $($task.TaskPath)$($task.TaskName)")
    }

    # Sem elevacao a chave OEM do firmware volta vazia, e ai o indicio mais forte
    # -- canal KMS numa maquina OEM -- nunca dispara. Um 'nao detectei' obtido
    # assim precisa vir marcado, senao vira falsa tranquilidade.
    [PSCustomObject]@{
        Detected      = ($evidence.Count -gt 0)
        Limitado      = $limitado
        KmsChannel    = ($kmsChannel.Count -gt 0)
        KmsMachine    = $kmsMachine
        OemKeyPresent = (-not [string]::IsNullOrWhiteSpace($oemKey))
        RenewalTasks  = @($tasks | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
        Evidence      = @($evidence)
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

    $null = Get-WpaSupportedWindows
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

function Invoke-WpaSystemProbe {
    <#
      Le a arvore WPA como SYSTEM. A contagem sozinha nunca explicou nada: o que
      explica e quantas subchaves o administrador NAO enxerga e quantos perfis de
      ACL distintos existem ali. Por isso o PsExec paga o proprio custo.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PsExecPath)

    $null = Get-WpaSupportedWindows
    Require-Admin
    if (-not (Test-WpaPsExec64File -Path $PsExecPath)) {
        throw 'PsExec64 ausente ou sem assinatura Microsoft valida.'
    }

    $powershell = Join-Path (Get-WindowsDirectory) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
        throw "Windows PowerShell ausente: $powershell"
    }

    # Gemeo de Get-WpaAclSample, repetido de proposito: este bloco roda noutro
    # processo, sem o modulo carregado, entao nao da para chamar a funcao. O passo
    # de amostragem e deterministico dos dois lados, e por isso SYSTEM e
    # administrador acabam lendo as mesmas subchaves -- e a diferenca entre o que
    # cada um consegue abrir vira o sinal.
    $command = @'
$ErrorActionPreference = 'Stop'
$path = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\WPA'
$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\WPA')
$total = [int]$key.SubKeyCount
$names = @($key.GetSubKeyNames())
$key.Dispose()
$limit = 400
$sample = $names
if ($names.Count -gt $limit) {
    $step = [int][Math]::Ceiling($names.Count / $limit)
    $sample = @(for ($i = 0; $i -lt $names.Count; $i += $step) { $names[$i] })
}
$groups = @{}
$unreadable = 0
foreach ($name in $sample) {
    $sddl = '<ILEGIVEL>'
    try { $sddl = (Get-Acl -LiteralPath "$path\$name").Sddl } catch { $unreadable++ }
    if ($groups.ContainsKey($sddl)) { $groups[$sddl]++ } else { $groups[$sddl] = 1 }
}
$owner = '<ILEGIVEL>'
try { $owner = (Get-Acl -LiteralPath $path).Owner } catch { }
[pscustomobject]@{
    Count      = $total
    Listed     = $names.Count
    Sampled    = @($sample).Count
    Unreadable = $unreadable
    RootOwner  = $owner
    AclGroups  = @($groups.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Subkeys = $_.Value; Sddl = $_.Key }
    })
} | ConvertTo-Json -Depth 4 -Compress
'@
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

        $json = (Get-Content -LiteralPath $standardOutput -Raw -ErrorAction Stop).Trim()
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw 'A consulta WPA como SYSTEM nao retornou dados.'
        }
        $probe = $json | ConvertFrom-Json -ErrorAction Stop

        # A contagem total sai do hive e e a mesma para os dois: o que separa
        # SYSTEM de administrador nao e quantas subchaves existem, e quantas dao
        # para abrir. Por isso a diferenca e medida sobre a amostra, nao sobre o
        # total -- e o relatorio diz que e amostra.
        $adminSample = Get-WpaAclSample
        Registrar-Log 'Consulta somente leitura de WPA como SYSTEM concluida'
        return [PSCustomObject]@{
            SystemCount      = [int]$probe.Count
            AdminCount       = [int]$adminSample.Count
            SampleSize       = [int]$probe.Sampled
            SystemUnreadable = [int]$probe.Unreadable
            AdminUnreadable  = [int]$adminSample.Unreadable
            HiddenFromAdmin  = ([int]$adminSample.Unreadable - [int]$probe.Unreadable)
            RootOwner        = [string]$probe.RootOwner
            AclProfiles      = @($probe.AclGroups).Count
            AclGroups        = @($probe.AclGroups)
        }
    }
    finally {
        Remove-Item -LiteralPath $standardOutput, $standardError -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WpaActivationRepair {
    $null = Get-WpaSupportedWindows
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
    $null = Get-WpaSupportedWindows
    Require-Admin
    Invoke-Slmgr -Operation '/rilc'
    Registrar-Log 'Reinstalacao das licencas conhecidas concluida via slmgr /rilc'
}

# ---------------------------------------------------------------------------
# Arsenal de correcao. Ordenado do menos ao mais invasivo. Nenhuma etapa apaga
# HKLM\SYSTEM\WPA: nao existe contrato oficial para reconstruir essa arvore.
# ---------------------------------------------------------------------------

function Get-WpaActivationState {
    <#
      Estado agregado do licenciamento. Sair de 'Sem licenca' para um periodo de
      grace e progresso real, entao a escada de reparo precisa distinguir os dois
      em vez de tratar tudo que nao e 1 como o mesmo fracasso.
    #>
    $statuses = @(Get-CimInstance -ClassName SoftwareLicensingProduct `
            -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue |
        ForEach-Object { [int]$_.LicenseStatus })

    $code = if ($statuses -contains 1) { 1 }
            elseif ($statuses.Count -gt 0) { ($statuses | Sort-Object -Descending)[0] }
            else { 0 }

    [PSCustomObject]@{
        Licensed   = ($code -eq 1)
        StatusCode = $code
        StatusText = (Get-WpaLicenseStatusText -Status $code)
    }
}

function Get-WpaLicenseDetail {
    # Saida oficial do slmgr: /dlv (detalhado), /dli (resumo), /xpr (expiracao).
    $null = Get-WpaSupportedWindows
    foreach ($operation in '/dlv', '/dli', '/xpr') {
        [PSCustomObject]@{
            Operation = $operation
            Output    = ((Invoke-Slmgr -Operation $operation -Quiet) -join [Environment]::NewLine)
        }
    }
}

function Invoke-WpaLicensingDiag {
    # Ferramenta oficial da Microsoft: gera relatorio XML e um cab com os logs.
    $null = Get-WpaSupportedWindows
    Require-Admin
    $executable = Join-Path (Get-WindowsDirectory) 'System32\licensingdiag.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Arquivo nativo ausente: $executable"
    }

    $directory = Get-SyncMasterDataDir -SubPasta 'Relatorios\WPA'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $report = Join-Path $directory "licensingdiag-$stamp.xml"
    $log = Join-Path $directory "licensingdiag-$stamp.cab"
    & $executable '-report' $report '-log' $log
    if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
        throw "licensingdiag.exe nao gerou o relatorio em $report."
    }
    Registrar-Log "Relatorio licensingdiag gerado em $report"
    return [PSCustomObject]@{ Report = $report; Log = $log }
}

function Export-WpaReport {
    # Junta diagnostico, licencas e a saida do slmgr num unico arquivo de texto.
    $diagnostic = Get-WpaDiagnostic
    $directory = Get-SyncMasterDataDir -SubPasta 'Relatorios\WPA'
    $file = Join-Path $directory ('wpa-{0:yyyyMMdd-HHmmss}.txt' -f (Get-Date))

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('=== DIAGNOSTICO WPA / SPP ===')
    $lines.Add(($diagnostic | Select-Object Windows, Version, Build, CapturedAt, WpaSubkeyCount,
            HiveMegaBytes, SppsvcStatus, SppsvcStartType, SppsvcProcessId, SppsvcCpuSeconds, SppErrors7Days |
            Format-List | Out-String).Trim())
    if ($diagnostic.Licenses.Count -gt 0) {
        $lines.Add('')
        $lines.Add('=== LICENCAS ===')
        $lines.Add(($diagnostic.Licenses | Format-Table -AutoSize | Out-String).Trim())
    }
    foreach ($section in Get-WpaLicenseDetail) {
        $lines.Add('')
        $lines.Add("=== slmgr.vbs $($section.Operation) ===")
        $lines.Add($section.Output)
    }

    Set-Content -LiteralPath $file -Value $lines -Encoding UTF8 -ErrorAction Stop
    Registrar-Log "Relatorio WPA salvo em $file"
    return $file
}

function Backup-WpaRegistry {
    # Exporta HKLM\SYSTEM\WPA para .reg. Pre-requisito das correcoes invasivas.
    $null = Get-WpaSupportedWindows
    Require-Admin
    $directory = Get-SyncMasterDataDir -SubPasta 'Backups\WPA'
    $file = Join-Path $directory ('WPA-{0:yyyyMMdd-HHmmss}.reg' -f (Get-Date))
    $registryTool = Join-Path (Get-WindowsDirectory) 'System32\reg.exe'

    $output = & $registryTool 'export' 'HKLM\SYSTEM\WPA' $file '/y' 2>&1
    $written = (Test-Path -LiteralPath $file -PathType Leaf) -and
               ((Get-Item -LiteralPath $file).Length -gt 0)
    if (-not $written) {
        throw "Nao foi possivel exportar a chave WPA: $($output -join ' ')"
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'A exportacao terminou com aviso; parte das subchaves pode nao estar no arquivo.'
    }
    # Honestidade: reimportar essa arvore nao desfaz um /upk nem devolve licenca.
    # O arquivo serve para comparar antes/depois e para levar ao suporte.
    Write-Warning 'O .reg preserva evidencia da arvore WPA; ele NAO restaura licenca nem desfaz /upk.'
    Registrar-Log "Backup da chave WPA gravado em $file"
    return $file
}

function Repair-WpaServices {
    # Reabilita e inicia sppsvc/ClipSVC. Causa comum apos "debloaters" e tweaks.
    $null = Get-WpaSupportedWindows
    Require-Admin
    $wanted = @(
        [PSCustomObject]@{ Name = 'sppsvc'; StartType = 'Automatic' }
        [PSCustomObject]@{ Name = 'ClipSVC'; StartType = 'Manual' }
    )

    foreach ($item in $wanted) {
        $service = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
        if (-not $service) {
            [PSCustomObject]@{ Servico = $item.Name; Acao = 'Servico ausente'; Status = $null }
            continue
        }

        $actions = @()
        if ([string]$service.StartType -eq 'Disabled') {
            Set-Service -Name $item.Name -StartupType $item.StartType -ErrorAction Stop
            $actions += "inicializacao ajustada para $($item.StartType)"
        }
        try {
            if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
                Start-Service -Name $item.Name -ErrorAction Stop
                $actions += 'iniciado'
            }
        }
        catch { $actions += "falha ao iniciar: $($_.Exception.Message)" }
        if ($actions.Count -eq 0) { $actions = @('ja estava correto') }

        [PSCustomObject]@{
            Servico = $item.Name
            Acao    = ($actions -join '; ')
            Status  = [string](Get-Service -Name $item.Name -ErrorAction SilentlyContinue).Status
        }
    }
    Registrar-Log 'Servicos de licenciamento (sppsvc/ClipSVC) verificados e reparados'
}

function Clear-WpaKmsConfig {
    # Limpa o nome de KMS gravado na maquina e tenta a ativacao oficial de novo.
    $null = Get-WpaSupportedWindows
    Require-Admin
    Invoke-Slmgr -Operation '/ckms'
    Invoke-Slmgr -Operation '/ato'
    Registrar-Log 'Configuracao de KMS residual limpa e ativacao oficial tentada'
}

function Reset-WpaTokens {
    <#
      Reconstroi o armazenamento de licencas (tokens.dat). O arquivo antigo e
      RENOMEADO, nunca apagado, e a chave de registro e exportada antes.
    #>
    $null = Get-WpaSupportedWindows
    Require-Admin
    $registryBackup = Backup-WpaRegistry

    $store = Join-Path (Get-WindowsDirectory) 'ServiceProfiles\LocalService\AppData\Local\Microsoft\WSLicense'
    $tokens = Join-Path $store 'tokens.dat'
    if (-not (Test-Path -LiteralPath $tokens -PathType Leaf)) {
        throw "Armazenamento de licencas nao encontrado: $tokens"
    }

    $service = Get-Service -Name sppsvc -ErrorAction Stop
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name sppsvc -Force -ErrorAction Stop
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,
            [timespan]::FromSeconds(30))
    }

    $newName = 'tokens-{0:yyyyMMdd-HHmmss}.bak' -f (Get-Date)
    $renamed = $false
    foreach ($attempt in 1..5) {
        try {
            Rename-Item -LiteralPath $tokens -NewName $newName -ErrorAction Stop
            $renamed = $true
            break
        }
        catch { Start-Sleep -Seconds 2 }
    }
    if (-not $renamed) {
        Start-Service -Name sppsvc -ErrorAction SilentlyContinue
        throw 'O tokens.dat continua em uso. Reinicie o computador e tente de novo.'
    }

    Start-Service -Name sppsvc -ErrorAction Stop
    Invoke-Slmgr -Operation '/rilc'
    Invoke-Slmgr -Operation '/ato'
    Registrar-Log "tokens.dat renomeado para $newName e licencas reinstaladas"
    return [PSCustomObject]@{
        TokensBackup   = (Join-Path $store $newName)
        RegistryBackup = $registryBackup
    }
}

function Repair-WpaSystemFiles {
    # DISM /RestoreHealth e SFC /scannow: binarios de licenciamento corrompidos.
    Require-Admin
    $system32 = Join-Path (Get-WindowsDirectory) 'System32'
    $steps = @(
        [PSCustomObject]@{ Executable = 'Dism.exe'; Arguments = @('/Online', '/Cleanup-Image', '/RestoreHealth'); Accepted = @(0, 3010) }
        [PSCustomObject]@{ Executable = 'sfc.exe'; Arguments = @('/scannow'); Accepted = @(0) }
    )

    foreach ($step in $steps) {
        $path = Join-Path $system32 $step.Executable
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Arquivo nativo ausente: $path"
        }
        Write-Host "Executando $($step.Executable) $($step.Arguments -join ' ')... isso demora." -ForegroundColor Yellow
        & $path @($step.Arguments)
        if ($LASTEXITCODE -notin $step.Accepted) {
            throw "$($step.Executable) falhou com codigo $LASTEXITCODE."
        }
    }
    Registrar-Log 'DISM /RestoreHealth e SFC /scannow concluidos'
}

function Uninstall-WpaProductKey {
    # /upk desinstala a chave em uso; /cpky tira a copia dela do registro.
    $null = Get-WpaSupportedWindows
    Require-Admin
    $null = Backup-WpaRegistry
    Invoke-Slmgr -Operation '/upk'
    Invoke-Slmgr -Operation '/cpky'
    Registrar-Log 'Chave de produto desinstalada (/upk) e copia limpa do registro (/cpky)'
}

function Invoke-WpaRearm {
    # Reinicia os temporizadores de licenciamento. Contagem limitada; exige reiniciar.
    $null = Get-WpaSupportedWindows
    Require-Admin
    $null = Backup-WpaRegistry
    Invoke-Slmgr -Operation '/rearm'
    Registrar-Log 'slmgr /rearm executado; reinicializacao necessaria'
}

function Invoke-WpaPhoneActivation {
    <#
      Caminho oficial quando a ativacao pela internet nao passa (rede bloqueada,
      reinstalacao em hardware ja licenciado). /dti mostra o ID de instalacao que
      a central pede; /atp grava o ID de confirmacao que ela devolve.
    #>
    [CmdletBinding()]
    param([string]$ConfirmationId)

    $null = Get-WpaSupportedWindows
    Require-Admin

    if (-not $ConfirmationId) {
        Write-Host 'ID de instalacao (leia para a central):' -ForegroundColor Cyan
        Invoke-Slmgr -Operation '/dti'
        Write-Host 'Ligue para a central de ativacao. O assistente oficial (slui 4) mostra o numero do seu pais.' -ForegroundColor Yellow
        $ConfirmationId = Read-Host 'ID de confirmacao (48 digitos; Enter cancela)'
        if (-not $ConfirmationId) {
            Write-Host 'Cancelado.' -ForegroundColor DarkGray
            return
        }
    }

    Invoke-Slmgr -Operation '/atp' -ConfirmationId $ConfirmationId
    Registrar-Log 'Ativacao por telefone concluida via /atp'
}

function Invoke-WpaGuidedRepair {
    <#
      Escada de reparo: para no primeiro degrau que deixar o Windows licenciado.
      Cada degrau pede confirmacao. Nenhum degrau apaga a arvore de registro.
    #>
    $null = Get-WpaSupportedWindows
    Require-Admin
    $state = Get-WpaActivationState
    if ($state.Licensed) {
        Write-Host 'O Windows ja consta como licenciado. Nada a corrigir.' -ForegroundColor Green
        return
    }
    Write-Host "Estado inicial: $($state.StatusText)" -ForegroundColor Cyan

    $steps = @(
        [PSCustomObject]@{ Nome = 'Reparar servicos sppsvc/ClipSVC'; Acao = { Repair-WpaServices | Format-Table -AutoSize | Out-Host } }
        [PSCustomObject]@{ Nome = 'Reiniciar sppsvc e ativar (/ato)'; Acao = { Invoke-WpaActivationRepair } }
        [PSCustomObject]@{ Nome = 'Reinstalar licencas conhecidas (/rilc)'; Acao = { Invoke-WpaLicenseFileRepair; Invoke-Slmgr -Operation '/ato' } }
        [PSCustomObject]@{ Nome = 'Limpar KMS residual (/ckms + /ato)'; Acao = { Clear-WpaKmsConfig } }
        [PSCustomObject]@{ Nome = 'Reconstruir tokens.dat'; Acao = { Reset-WpaTokens | Format-List | Out-Host } }
        [PSCustomObject]@{ Nome = 'DISM /RestoreHealth + SFC /scannow'; Acao = { Repair-WpaSystemFiles; Invoke-Slmgr -Operation '/ato' } }
    )

    foreach ($step in $steps) {
        if (-not (Confirm-Action "Executar o degrau: $($step.Nome)?")) {
            Write-Host "Degrau ignorado: $($step.Nome)" -ForegroundColor DarkGray
            continue
        }
        try { & $step.Acao }
        catch { Write-Warning "$($step.Nome) falhou: $($_.Exception.Message)" }

        $newState = Get-WpaActivationState
        if ($newState.Licensed) {
            Write-Host "Windows licenciado apos: $($step.Nome)" -ForegroundColor Green
            Registrar-Log "Reparo guiado concluido no degrau: $($step.Nome)"
            return
        }
        if ($newState.StatusCode -ne $state.StatusCode) {
            Write-Host "Progresso: '$($state.StatusText)' virou '$($newState.StatusText)' apos: $($step.Nome)" -ForegroundColor Cyan
        }
        else {
            Write-Host "Ainda em '$($newState.StatusText)' apos: $($step.Nome)" -ForegroundColor Yellow
        }
        $state = $newState
    }

    Write-Warning "A escada terminou em '$($state.StatusText)'. Tente a ativacao por telefone ou leve o relatorio ao Suporte da Microsoft."
    Registrar-Log 'Reparo guiado terminou sem ativacao'
}

function Get-WpaReactivationRisk {
    <#
      O reset offline zera o tokens.dat e o armazenamento SPP inteiro, e nao
      reativa nada depois. Entao a pergunta que decide se vale correr o risco nao
      e 'a arvore esta inchada?', e 'esta maquina reativa sozinha depois?'.
      Chave no firmware reativa sem intervencao; volume por KMS depende do
      servidor responder; chave avulsa depende de alguem ter guardado a chave.
      O procedimento de origem nao faz essa pergunta -- e ela que separa
      'reiniciou e nem percebeu' de 'ficou sem Windows ativado e sem chave'.
    #>
    $null = Get-WpaSupportedWindows

    $oemKey = $null
    $elevado = Test-IsAdmin
    try {
        $oemKey = [string](Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop).OA3xOriginalProductKey
    }
    catch { Write-Verbose "SoftwareLicensingService indisponivel: $($_.Exception.Message)" }

    $produto = Get-CimInstance -ClassName SoftwareLicensingProduct `
        -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $canal = [string]$produto.Description
    $estado = Get-WpaActivationState
    $temFirmware = -not [string]::IsNullOrWhiteSpace($oemKey)

    # Sem elevacao a chave do firmware volta vazia, e e exatamente ela que decide
    # o desfecho. Um 'risco baixo' obtido assim seria chute, nao diagnostico.
    if (-not $elevado) {
        $risco = 'Desconhecido'
        $motivo = 'Sem elevacao a chave OEM do firmware nao e legivel, e e ela que decide se a maquina reativa sozinha.'
        $recomendacao = 'Reabra o Sync Master como administrador e consulte de novo ANTES de decidir.'
    }
    elseif ($canal -match 'KMSCLIENT') {
        $risco = 'Alto'
        $motivo = 'Licenca de volume por KMS: a ativacao depende de um servidor KMS responder na rede.'
        $recomendacao = 'Confirme que o KMS da empresa responde, ou tenha uma chave MAK em maos, antes de reiniciar.'
    }
    elseif ($canal -match 'MAK') {
        $risco = 'Alto'
        $motivo = 'Licenca de volume MAK: a chave nao fica no firmware e nao volta sozinha.'
        $recomendacao = 'Tenha a chave MAK em maos. Sem ela a maquina fica sem ativacao apos o reset.'
    }
    elseif ($temFirmware) {
        $risco = 'Baixo'
        $motivo = 'Ha chave OEM gravada no firmware: apos o reset o Windows le a chave da UEFI e reativa sem intervencao.'
        $recomendacao = 'Pode prosseguir. Ainda assim guarde o relatorio antes, para comparar depois.'
    }
    else {
        $risco = 'Medio'
        $motivo = 'Sem chave no firmware. Licenca digital costuma reativar online sozinha, mas chave avulsa digitada precisa ser digitada de novo.'
        $recomendacao = 'Confirme a licenca digital vinculada a conta Microsoft, ou guarde a chave, antes de reiniciar.'
    }

    [PSCustomObject]@{
        Risco             = $risco
        Motivo            = $motivo
        Recomendacao      = $recomendacao
        Canal             = $canal
        ChaveNoFirmware   = $temFirmware
        ChaveParcial      = [string]$produto.PartialProductKey
        Licenciado        = $estado.Licensed
        EstadoAtual       = $estado.StatusText
        ConsultaCompleta  = $elevado
    }
}

function Invoke-WpaOfflineResetGuide {
    <#
      Guia do reset offline do licenciamento (procedimento da massgrave.dev, que
      usa o rearm.cmd do projeto asdcorp/rearm). O Sync Master NAO apaga a arvore
      e NAO baixa o script: a chave WPA e protegida pelo kernel e so cede com o
      hive descarregado, fora do Windows, o que nenhuma funcao daqui alcanca.
      O que da para fazer daqui e o que o procedimento de origem nao faz: medir o
      estado antes, guardar evidencia, e dizer se esta maquina reativa sozinha
      depois. Reiniciar para o WinRE fica atras de confirmacao explicita.
    #>
    [CmdletBinding()]
    param([switch]$Reiniciar)

    $null = Get-WpaSupportedWindows

    Write-Host ''
    Write-Host '--- RESET OFFLINE DO LICENCIAMENTO (roda FORA do Windows) ---' -ForegroundColor Cyan

    try {
        $hive = Get-WpaHiveSize
        Write-Host ("Hive SYSTEM agora: {0} MB{1}" -f $hive.MegaBytes,
            $(if ($hive.Inchado) { ' (inchado)' } else { ' (dentro do normal)' })) -ForegroundColor Cyan
    }
    catch { Write-Warning "Tamanho do hive indisponivel: $($_.Exception.Message)" }

    try {
        $amostra = Get-WpaSample
        Write-Host "Subchaves em HKLM\SYSTEM\WPA: $($amostra.SubkeyCount)" -ForegroundColor Cyan
    }
    catch { Write-Warning "Contagem de subchaves indisponivel: $($_.Exception.Message)" }

    Write-Host ''
    Write-Host 'O que o rearm.cmd apaga (bem mais que as subchaves WPA):' -ForegroundColor Yellow
    foreach ($item in @(
            'chaves WPA da familia 8DEC0AF1-0341-4b93-85CD-72606C2DF94C',
            'tokens.dat do ClipSVC, do OSPPSVC e das pastas de licenciamento legadas',
            'data.dat e os caches de spp\store',
            'ClipSVC\Parameters\SubscriptionList (assinaturas e apps da Store)',
            'valores do SoftwareProtectionPlatform (ServiceSessionId, LicStatusArray, PolicyValuesArray, actionlist)',
            'caches de licenciamento do Office -- o Office tambem sai desativado',
            'entradas IdentityCRL em tres perfis')) {
        Write-Host "  - $item"
    }
    Write-Host 'Ele NAO reativa nada depois. A reativacao e por sua conta.' -ForegroundColor Yellow

    Write-Host ''
    $risco = $null
    try {
        $risco = Get-WpaReactivationRisk
        $cor = switch ($risco.Risco) { 'Baixo' { 'Green' } 'Medio' { 'Yellow' } default { 'Red' } }
        Write-Host "RISCO DE NAO REATIVAR: $($risco.Risco)" -ForegroundColor $cor
        Write-Host "  Canal:        $($risco.Canal)"
        Write-Host "  Chave parcial: $($risco.ChaveParcial)  (anote antes de prosseguir)"
        Write-Host "  Motivo:       $($risco.Motivo)"
        Write-Host "  Recomendacao: $($risco.Recomendacao)" -ForegroundColor Cyan
    }
    catch { Write-Warning "Nao foi possivel avaliar o risco de reativacao: $($_.Exception.Message)" }

    Write-Host ''
    Write-Host 'Procedimento (fonte: https://massgrave.dev/fix-wpa-registry):' -ForegroundColor Cyan
    foreach ($passo in @(
            '1. Baixe https://github.com/asdcorp/rearm/archive/refs/heads/principalis.zip e extraia.',
            '2. Copie rearm.cmd para a raiz do disco C: (C:\rearm.cmd).',
            '3. Reinicie para o ambiente de recuperacao: shutdown /f /r /o /t 0',
            '4. Solucao de Problemas > Opcoes Avancadas > Prompt de Comando.',
            '5. Rode C:\rearm.cmd  (se disser que nao reconhece, descubra a letra com:',
            '   bcdedit | find "osdevice"  e use a letra que aparecer, ex.: E:\rearm.cmd)',
            '6. Espere terminar, saia e inicie o Windows normalmente.',
            '7. Volte aqui e rode a triagem (opcao 0) para comparar hive e contagem.')) {
        Write-Host "  $passo"
    }
    Write-Host ''
    Write-Host 'O Sync Master nao baixa nem executa o rearm.cmd: a aquisicao e a execucao sao suas.' -ForegroundColor DarkGray

    if (-not $Reiniciar) { return $risco }

    if ($risco -and $risco.Risco -in 'Alto','Desconhecido') {
        Write-Warning "Risco $($risco.Risco): $($risco.Recomendacao)"
    }
    Write-Warning 'Reiniciar agora fecha os programas abertos a forca e descarta o que nao estiver salvo.'
    if (-not (Confirm-Action 'Guardar o relatorio e reiniciar AGORA para o ambiente de recuperacao?')) {
        Write-Host 'Cancelado. Nada foi alterado.' -ForegroundColor DarkGray
        return $risco
    }

    # Evidencia antes de um caminho sem volta: depois do reset nao da para
    # reconstruir qual era o estado, e o relatorio e o unico registro do antes.
    try { Write-Host "Relatorio salvo em: $(Export-WpaReport)" -ForegroundColor Green }
    catch { Write-Warning "Nao foi possivel salvar o relatorio: $($_.Exception.Message)" }

    Registrar-Log 'Reinicio para o ambiente de recuperacao solicitado (reset offline do licenciamento)'
    Start-Process -FilePath (Join-Path (Get-WindowsDirectory) 'System32\shutdown.exe') `
        -ArgumentList '/f','/r','/o','/t','0' -Wait -NoNewWindow -ErrorAction Stop
    return $risco
}

function Invoke-WpaTriage {
    <#
      Orquestrador da triagem. Chama os coletores que ja existem na ordem do mais
      barato para o mais caro e termina sempre com um veredito e um proximo passo
      concreto. Nenhum coletor derruba os outros: o que falhar vira aviso com a
      orientacao do que fazer (elevar, instalar o PsExec, tentar com rede), porque
      diagnostico que morre calado no meio nao serve para nada.

      Ordem: tamanho do hive -> rastro de ativador -> diagnostico geral ->
      crescimento -> sonda como SYSTEM (opcional, cara e com dependencia externa).
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(5,600)][int]$Seconds = 120,
        [switch]$IncluirSondaSystem
    )

    $null = Get-WpaSupportedWindows
    $avisos = [System.Collections.Generic.List[string]]::new()

    $hive = $null
    try { $hive = Get-WpaHiveSize }
    catch {
        $avisos.Add("Tamanho do hive SYSTEM indisponivel ($($_.Exception.Message)). Reabra o Sync Master como administrador para ler esse sinal.")
    }

    $ativador = $null
    try { $ativador = Test-WpaActivatorFootprint }
    catch { $avisos.Add("Rastreio de ativador incompleto: $($_.Exception.Message)") }

    $diagnostico = $null
    try { $diagnostico = Get-WpaDiagnostic }
    catch { $avisos.Add("Diagnostico geral falhou: $($_.Exception.Message)") }

    $estado = $null
    try { $estado = Get-WpaActivationState }
    catch { $avisos.Add("Estado de licenca indisponivel: $($_.Exception.Message)") }

    # Unico passo que custa tempo de parede, e o unico que separa 'esta
    # acontecendo agora' de 'ja aconteceu e parou'.
    $crescimento = $null
    try { $crescimento = Measure-WpaGrowth -Seconds $Seconds }
    catch { $avisos.Add("Medicao de crescimento falhou: $($_.Exception.Message)") }

    $sonda = $null
    if ($IncluirSondaSystem) {
        try {
            $psExec = Find-WpaPsExec64
            if (-not $psExec) {
                throw 'PsExec64 nao foi encontrado; a opcao 3 do menu instala e valida a assinatura antes de usar.'
            }
            $sonda = Invoke-WpaSystemProbe -PsExecPath $psExec
        }
        catch { $avisos.Add("Sonda como SYSTEM nao rodou: $($_.Exception.Message)") }
    }

    $inchado = ($null -ne $hive -and $hive.Inchado) -or
               ($null -ne $diagnostico -and $diagnostico.WpaSubkeyCount -gt 50000)
    $crescendo = ($null -ne $crescimento -and $crescimento.NewSubkeys -gt 0)
    $licenciado = ($null -ne $estado -and $estado.Licensed)

    if ($null -ne $ativador -and $ativador.Detected) {
        $veredito = 'ATIVADOR PRESENTE'
        $proximo = 'Remova o ativador e as tarefas agendadas dele ANTES de qualquer reparo: enquanto ele renovar, toda correcao volta atras em horas. Depois disso use o reparo guiado (opcao 16).'
    }
    elseif ($crescendo) {
        $veredito = 'CRESCENDO AGORA'
        $proximo = "A arvore ganhou $($crescimento.NewSubkeys) subchave(s) em $($crescimento.Seconds)s, entao alguma coisa esta reativando em ciclo. Confira licenca e eventos Security-SPP acima; se o Windows nao consta licenciado, o reparo guiado (opcao 16) ataca a causa. Nao adianta encolher a arvore com a causa viva."
    }
    elseif ($null -ne $estado -and -not $licenciado) {
        $veredito = "LICENCA NAO ATIVA ($($estado.StatusText))"
        $proximo = 'Use o reparo guiado (opcao 16): ele sobe do mais barato ao mais invasivo e para no degrau que licenciar. Sem rede para o /ato, tente a ativacao por telefone (opcao 17).'
    }
    elseif ($inchado) {
        $veredito = 'CICATRIZ ANTIGA'
        $proximo = 'Windows licenciado e arvore parada: o inchaco e rastro do que ja passou, nao causa ativa. O Sync Master nao encolhe HKLM\SYSTEM\WPA porque nao existe contrato oficial de reconstrucao, e uma arvore grande e parada nao quebra o licenciamento. Guarde o relatorio (opcao 5) e siga.'
    }
    elseif ($licenciado -and $null -ne $diagnostico) {
        $veredito = 'NORMAL'
        $proximo = 'Licenciado, arvore no tamanho esperado e sem crescimento no intervalo. Nada a corrigir.'
    }
    else {
        $veredito = 'INCONCLUSIVO'
        $proximo = 'Faltou dado para concluir -- veja os avisos acima. Rode como administrador e, se o caso persistir, gere o relatorio oficial (opcao 6) e a sonda como SYSTEM (opcao 3).'
    }

    if ($null -ne $ativador -and -not $ativador.Detected -and $ativador.Limitado) {
        $avisos.Add('O rastreio de ativador rodou sem elevacao: a chave OEM do firmware nao e legivel assim, entao "nenhum ativador" aqui vale menos. Reabra o Sync Master como administrador antes de descartar essa hipotese.')
    }
    if (-not $IncluirSondaSystem -and ($crescendo -or $inchado)) {
        $avisos.Add('A sonda como SYSTEM (opcao 3) mostra quantas subchaves o administrador nao consegue abrir. E ai que o crescimento costuma se esconder.')
    }

    Write-Host ''
    Write-Host "VEREDITO: $veredito" -ForegroundColor Cyan
    Write-Host "PROXIMO PASSO: $proximo" -ForegroundColor Yellow
    foreach ($aviso in $avisos) { Write-Warning $aviso }
    Registrar-Log "Triagem WPA concluida: $veredito"

    [PSCustomObject]@{
        Veredito     = $veredito
        Proximo      = $proximo
        Avisos       = @($avisos)
        Hive         = $hive
        Ativador     = $ativador
        Diagnostico  = $diagnostico
        Estado       = $estado
        Crescimento  = $crescimento
        Sonda        = $sonda
    }
}

function Menu-GerenciamentoWpa {
    try { $null = Get-WpaSupportedWindows }
    catch {
        Write-Warning $_.Exception.Message
        Pause-Script
        return
    }

    do {
        Clear-Host
        Write-Host '--- WPA / PROTECAO DE SOFTWARE (WINDOWS 10/11 x64) ---' -ForegroundColor Cyan
        Write-Host '[ DIAGNOSTICO - somente leitura ]' -ForegroundColor DarkCyan
        Write-Host '0  - Triagem completa: roda tudo na ordem e diz o proximo passo' -ForegroundColor Green
        Write-Host '1  - Diagnostico geral (licenca, sppsvc, eventos, subchaves)'
        Write-Host '2  - Medir crescimento das subchaves WPA por um intervalo'
        Write-Host '3  - Sondar a arvore como SYSTEM: subchaves ocultas e perfis de ACL (PsExec64)'
        Write-Host '4  - Detalhes oficiais da licenca (slmgr /dlv, /dli, /xpr)'
        Write-Host '5  - Salvar relatorio completo em arquivo'
        Write-Host '6  - Relatorio oficial licensingdiag.exe (XML + cab)'
        Write-Host '[ CORRECAO - do menos ao mais invasivo ]' -ForegroundColor DarkCyan
        Write-Host '7  - Exportar HKLM\SYSTEM\WPA em .reg (evidencia; nao e rollback)'
        Write-Host '8  - Reparar servicos sppsvc/ClipSVC (reabilitar e iniciar)'
        Write-Host '9  - Reiniciar sppsvc e tentar ativacao oficial (/ato)'
        Write-Host '10 - Reinstalar licencas conhecidas (/rilc)'
        Write-Host '11 - Limpar configuracao de KMS residual (/ckms + /ato)'
        Write-Host '12 - Reconstruir o tokens.dat (backup + /rilc + /ato)'
        Write-Host '13 - Reparar arquivos do sistema (DISM /RestoreHealth + SFC)'
        Write-Host '14 - Desinstalar a chave de produto (/upk + /cpky)'
        Write-Host '15 - Rearm do licenciamento (/rearm; limitado, exige reiniciar)'
        Write-Host '16 - Reparo guiado escalonado (para quando ativar)' -ForegroundColor Yellow
        Write-Host '17 - Ativacao por telefone (/dti + /atp), quando a internet nao passa'
        Write-Host '18 - Reset offline do licenciamento: guia + risco de nao reativar' -ForegroundColor Yellow
        Write-Host 'A  - Abrir a pagina de Ativacao do Windows'
        Write-Host 'Q  - Voltar'
        Write-Warning 'A quantidade isolada de subchaves nao define saude. O Sync Master nunca apaga HKLM\SYSTEM\WPA.'
        $choice = Read-Host 'Sua escolha'

        try {
            switch ($choice.ToUpper()) {
                '0' {
                    Write-Host 'A triagem observa o WPA por 2 minutos antes de concluir.' -ForegroundColor Yellow
                    $comSonda = Confirm-Action 'Incluir a sonda como SYSTEM (exige PsExec64 e elevacao)?'
                    $triagem = Invoke-WpaTriage -Seconds 120 -IncluirSondaSystem:$comSonda
                    if ($triagem.Hive) {
                        Write-Host "Hive SYSTEM: $($triagem.Hive.MegaBytes) MB" -ForegroundColor Cyan
                    }
                    if ($triagem.Diagnostico) {
                        $triagem.Diagnostico | Select-Object Windows,Build,WpaSubkeyCount,SppsvcStatus,SppErrors7Days | Format-List
                    }
                    if ($triagem.Ativador -and $triagem.Ativador.Evidence.Count -gt 0) {
                        Write-Host 'Indicios de ativador:' -ForegroundColor Yellow
                        $triagem.Ativador.Evidence | ForEach-Object { Write-Host "  - $_" }
                    }
                    if ($triagem.Crescimento) { $triagem.Crescimento | Format-List }
                    Pause-Script
                }
                '1' {
                    $diagnostic = Get-WpaDiagnostic
                    $diagnostic | Select-Object Windows,Version,Build,CapturedAt,WpaSubkeyCount,HiveMegaBytes,
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
                    $probe = Invoke-WpaSystemProbe -PsExecPath $psExec
                    $probe | Select-Object SystemCount,AdminCount,SampleSize,SystemUnreadable,
                        AdminUnreadable,HiddenFromAdmin,RootOwner,AclProfiles | Format-List
                    if ($probe.HiddenFromAdmin -gt 0) {
                        Write-Warning "Na amostra de $($probe.SampleSize) subchave(s), $($probe.HiddenFromAdmin) so abrem para o SYSTEM. E ai que o crescimento se esconde."
                    }
                    $probe.AclGroups | Sort-Object Subkeys -Descending | Select-Object -First 5 |
                        Select-Object Subkeys,@{n='Sddl';e={ $_.Sddl.Substring(0, [Math]::Min(60, $_.Sddl.Length)) }} |
                        Format-Table -AutoSize
                    Pause-Script
                }
                '4' {
                    foreach ($section in Get-WpaLicenseDetail) {
                        Write-Host "--- slmgr.vbs $($section.Operation) ---" -ForegroundColor Cyan
                        Write-Host $section.Output
                    }
                    Pause-Script
                }
                '5' {
                    $file = Export-WpaReport
                    Write-Host "Relatorio salvo em: $file" -ForegroundColor Green
                    Pause-Script
                }
                '6' {
                    $generated = Invoke-WpaLicensingDiag
                    Write-Host "Relatorio: $($generated.Report)" -ForegroundColor Green
                    Write-Host "Logs:      $($generated.Log)" -ForegroundColor Green
                    Pause-Script
                }
                '7' {
                    $file = Backup-WpaRegistry
                    Write-Host "Backup gravado em: $file" -ForegroundColor Green
                    Pause-Script
                }
                '8' {
                    if (Confirm-Action 'Reabilitar e iniciar os servicos sppsvc e ClipSVC?') {
                        Repair-WpaServices | Format-Table -AutoSize
                    }
                    Pause-Script
                }
                '9' {
                    if (Confirm-Action 'Reiniciar graciosamente o sppsvc e executar slmgr.vbs /ato?') {
                        Invoke-WpaActivationRepair
                        Write-Host 'Servico reiniciado e tentativa de ativacao concluida.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '10' {
                    Write-Warning '/rilc reinstala licencas conhecidas; nao promete limpar ou reconstruir HKLM\SYSTEM\WPA.'
                    if (Confirm-Action 'Executar o reparo oficial slmgr.vbs /rilc?') {
                        Invoke-WpaLicenseFileRepair
                        Write-Host 'Reinstalacao de licencas concluida.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '11' {
                    Write-Warning 'Use somente em maquina de varejo/OEM que aponta para um KMS que nao existe mais.'
                    if (Confirm-Action 'Limpar o nome de KMS da maquina e tentar a ativacao oficial?') {
                        Clear-WpaKmsConfig
                        Write-Host 'Configuracao de KMS limpa e ativacao tentada.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '12' {
                    Write-Warning 'O tokens.dat sera renomeado (nunca apagado) e as licencas reinstaladas. O sppsvc para por alguns segundos.'
                    if (Confirm-Action 'Reconstruir o armazenamento de licencas tokens.dat?') {
                        Reset-WpaTokens | Format-List
                        Write-Host 'Armazenamento de licencas reconstruido.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '13' {
                    Write-Warning 'DISM e SFC podem levar de 15 a 60 minutos e exigem rede para o RestoreHealth.'
                    if (Confirm-Action 'Executar DISM /RestoreHealth seguido de SFC /scannow?') {
                        Repair-WpaSystemFiles
                        Write-Host 'Reparo dos arquivos do sistema concluido.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '14' {
                    Write-Warning 'O Windows fica SEM chave ate voce reinstalar uma. Tenha a chave em maos antes de continuar.'
                    if (Confirm-Action 'Desinstalar a chave de produto atual (/upk) e limpar a copia do registro (/cpky)?') {
                        Uninstall-WpaProductKey
                        Write-Host 'Chave desinstalada. Use a opcao de instalar chave de produto para reinstalar.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '15' {
                    Write-Warning 'O /rearm tem contagem limitada (em geral 3 por instalacao) e so vale apos reiniciar.'
                    if (Confirm-Action 'Executar slmgr.vbs /rearm?') {
                        Invoke-WpaRearm
                        Write-Host 'Rearm concluido. Reinicie o computador para valer.' -ForegroundColor Green
                    }
                    Pause-Script
                }
                '16' {
                    Invoke-WpaGuidedRepair
                    Pause-Script
                }
                '17' {
                    Write-Warning 'Use quando /ato nao passa por rede. Voce vai precisar ligar para a central da Microsoft.'
                    if (Confirm-Action 'Iniciar a ativacao por telefone (/dti + /atp)?') {
                        Invoke-WpaPhoneActivation
                    }
                    Pause-Script
                }
                '18' {
                    Write-Warning 'Este caminho roda FORA do Windows e apaga o armazenamento de licenca (Windows e Office). Nao ha rollback.'
                    $guia = Invoke-WpaOfflineResetGuide
                    if ($guia -and $guia.Risco -eq 'Baixo' -and
                        (Confirm-Action 'Reiniciar agora para o ambiente de recuperacao?')) {
                        Invoke-WpaOfflineResetGuide -Reiniciar | Out-Null
                    }
                    Pause-Script
                }
                'A' {
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
