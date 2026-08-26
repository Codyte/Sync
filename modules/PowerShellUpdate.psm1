# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L31    Invoke-PowerShellRequest
#   L72    Get-VersionFromReleaseUrl
#   L84    Get-LatestPowerShellVersion
#   L141   Invoke-WingetInstall
#   L168   Install-PowerShellFromMsi
#   L203   Start-PowerShellInstallation
#   L229   Find-PwshPath
#   L254   Install-PowerShellPortable
#   L340   Install-PowerShell7
#   L374   Get-InstallerInfo
#   L400   Menu-AtualizacaoPowerShell
# ======================= END NAV INDEX =======================

<#
    PowerShellUpdate.psm1 — atualizacao do PowerShell.
    Extraido do monolito legado (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

# Último recurso quando api.github.com E aka.ms estão bloqueados (rede corporativa).
# Não precisa estar sempre atualizada: só destrava o bootstrap; o pwsh instalado se atualiza depois.
$script:PinnedPSVersion = '7.5.2'
$script:GitHubHeaders = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'SyncMaster-PowerShell-Bootstrap'
}

function Invoke-PowerShellRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Rest', 'Download', 'Web')][string]$Kind,
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers,
        [string]$OutFile,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $request = @{
                Uri = $Uri
                UseBasicParsing = $true
                ErrorAction = 'Stop'
                TimeoutSec = 120
            }
            if ($Headers) { $request.Headers = $Headers }
            switch ($Kind) {
                'Rest' { return Invoke-RestMethod @request }
                'Web' { return Invoke-WebRequest @request }
                'Download' {
                    if ([string]::IsNullOrWhiteSpace($OutFile)) { throw 'OutFile e obrigatorio para download.' }
                    $request.OutFile = $OutFile
                    Invoke-WebRequest @request | Out-Null
                    return
                }
            }
        }
        catch {
            $statusCode = $null
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = $null }
            if ($attempt -eq $MaxAttempts -or $statusCode -eq 404) { throw }
            Write-Warning ("Falha de rede (tentativa {0}/{1}): {2}" -f $attempt, $MaxAttempts, $_.Exception.Message)
            Start-Sleep -Seconds ([math]::Pow(2, $attempt - 1))
        }
    }
}

function Get-VersionFromReleaseUrl {
    <#
      .SYNOPSIS  Extrai a versão de uma URL de release do PowerShell (função pura, testável).
      .EXAMPLE   Get-VersionFromReleaseUrl 'https://github.com/PowerShell/PowerShell/releases/tag/v7.5.2'  # -> 7.5.2
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory=$true)][string]$Url)
    if ($Url -match '/tag/v(\d+\.\d+\.\d+)') { return $Matches[1] }
    return $null
}

function Get-LatestPowerShellVersion {
    [CmdletBinding()]
    param (
        [switch]$Preview,
        # So o bootstrap (Install-PowerShell7) usa a versao pinada: o check de update do
        # startup NAO deve — offline viraria prompt de "atualize" a cada abertura.
        [switch]$UsePinnedFallback
    )
    try {
        if ($Preview) {
            Write-Host "Buscando a versão PREVIEW mais recente no GitHub..." -ForegroundColor Yellow
            $apiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases"
            $response = Invoke-PowerShellRequest -Kind Rest -Uri $apiUrl -Headers $script:GitHubHeaders
            $latestTag = ($response | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1).tag_name
        }
        else {
            Write-Host "Buscando a versão ESTÁVEL mais recente no GitHub..." -ForegroundColor Yellow
            $apiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
            $response = Invoke-PowerShellRequest -Kind Rest -Uri $apiUrl -Headers $script:GitHubHeaders
            $latestTag = $response.tag_name
        }
        if ($latestTag) {
            $version = $latestTag.TrimStart('v')
            Write-Host "Versão mais recente encontrada: $version" -ForegroundColor Green
            return $version
        }
    }
    catch {
        Write-Warning "api.github.com indisponível (bloqueio/rate-limit?). Tentando aka.ms..."
    }
    if ($Preview) { return $null }  # fallbacks abaixo só conhecem a stable

    # Fallback 1: aka.ms redireciona para a página da release estável — a versão vai na URL final.
    try {
        $resp = Invoke-PowerShellRequest -Kind Web -Uri 'https://aka.ms/powershell-release?tag=stable'
        # PS5 expõe a URL final em BaseResponse.ResponseUri; PS7 em RequestMessage.RequestUri
        $finalUrl = if ($resp.BaseResponse.PSObject.Properties['ResponseUri']) {
            $resp.BaseResponse.ResponseUri.AbsoluteUri
        } else {
            $resp.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
        }
        $version = Get-VersionFromReleaseUrl -Url $finalUrl
        if ($version) {
            Write-Host "Versão mais recente (via aka.ms): $version" -ForegroundColor Green
            return $version
        }
    }
    catch {
        Write-Warning "aka.ms também indisponível. Verifique sua conexão com a internet."
    }

    # Fallback 2: versão pinada — garante que o bootstrap nunca fica sem resposta.
    if (-not $UsePinnedFallback) { return $null }
    Write-Warning ("Usando versão pinada {0} (pode não ser a mais recente)." -f $script:PinnedPSVersion)
    return $script:PinnedPSVersion
}

function Invoke-WingetInstall {
    <#
      .SYNOPSIS  Instala/atualiza um pacote via winget tratando ausencia E codigo de saida.
      .DESCRIPTION  winget e exe nativo: exit code != 0 NAO lanca excecao, entao um try/catch
        nunca pegaria a falha. Aqui: 1) checa se winget existe (senao $false p/ fallback);
        2) inclui --accept-source-agreements (1o uso prompta o aceite da fonte e travaria o
        menu); 3) decide pelo $LASTEXITCODE. Devolve $true so em sucesso real.
      .OUTPUTS  [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory=$true)][string]$PackageId)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget não encontrado. Tentando download manual..."
        return $false
    }
    Write-Host "Usando winget para instalar/atualizar '$PackageId'..." -ForegroundColor Yellow
    winget install --id $PackageId -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Host "winget concluído com sucesso." -ForegroundColor Green
        return $true
    }
    Write-Warning ("winget retornou código {0}. Tentando download manual..." -f $LASTEXITCODE)
    return $false
}

function Install-PowerShellFromMsi {
    <#
      .SYNOPSIS  Valida a assinatura de um MSI do PowerShell e executa o msiexec.
      .DESCRIPTION  Compartilhado entre o download online (Start-PowerShellInstallation) e a
        instalação offline (MSI local, ex.: pendrive). Devolve $true só em sucesso real.
      .OUTPUTS  [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "MSI não encontrado: $Path"
        return $false
    }
    # Verifica a assinatura Authenticode antes de executar (cadeia valida + assinado pela Microsoft).
    $sig = Get-AuthenticodeSignature -FilePath $Path
    $signer = $sig.SignerCertificate.Subject
    if ($sig.Status -ne 'Valid' -or $signer -notmatch 'Microsoft') {
        Write-Warning ("Assinatura do instalador NAO confiavel (Status={0}; Signer={1}). ABORTANDO." -f $sig.Status, $signer)
        return $false
    }
    Write-Host "Assinatura válida (Microsoft). Iniciando o instalador..." -ForegroundColor Green
    # -PassThru p/ ler o ExitCode: msiexec nao seta $LASTEXITCODE e sem isto a falha/cancelamento
    # (1602/1603) passava como "concluida". 0 = ok; 3010 = ok mas exige reinicio.
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$Path`"" -Wait -PassThru
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        $reinicio = if ($proc.ExitCode -eq 3010) { ' (reinício pendente para concluir)' } else { '' }
        Write-Host ("Instalação concluída!$reinicio") -ForegroundColor Green
        return $true
    }
    Write-Warning ("Instalador msiexec retornou código {0} — instalação NÃO concluída. Execute como Administrador e tente novamente." -f $proc.ExitCode)
    return $false
}

function Start-PowerShellInstallation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [Parameter(Mandatory=$true)]
        [string]$InstallerUrl,
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath
    )
    Write-Host "Baixando PowerShell versão $Version..." -ForegroundColor Yellow
    Write-Host "URL: $InstallerUrl"
    try {
        Invoke-PowerShellRequest -Kind Download -Uri $InstallerUrl -Headers @{ 'User-Agent' = 'SyncMaster-PowerShell-Bootstrap' } -OutFile $InstallerPath
        Write-Host "Download concluído: $InstallerPath" -ForegroundColor Green
        if (-not (Install-PowerShellFromMsi -Path $InstallerPath)) {
            Remove-Item -LiteralPath $InstallerPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Falha ao baixar ou instalar o PowerShell $Version."
        Write-Warning "Verifique se a versão existe e se o script tem permissões de administrador."
        Write-Host "Consulte todas as versões disponíveis em: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Blue
    }
}

function Find-PwshPath {
    <#
      .SYNOPSIS  Localiza o pwsh.exe: PATH primeiro, depois caminhos padrão de instalação.
      .DESCRIPTION  Após instalar na MESMA sessão, o PATH do processo é velho e Get-Command
        falha — por isso os caminhos padrão (MSI em ProgramFiles, zip portátil em LOCALAPPDATA).
      .OUTPUTS  [string] caminho completo, ou $null se não encontrado.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $cmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source) { return $cmd.Source } else { return $cmd.Path }
    }
    # [IO.Path]::Combine e nao Join-Path: Join-Path valida o PSDrive e explode com drive inexistente
    $candidatos = @(
        [IO.Path]::Combine("$env:ProgramFiles", 'PowerShell', '7', 'pwsh.exe'),
        [IO.Path]::Combine("$env:LOCALAPPDATA", 'Microsoft', 'powershell', 'pwsh.exe')
    )
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Install-PowerShellPortable {
    <#
      .SYNOPSIS  Instala um ZIP oficial e versionado do PowerShell no perfil do usuario.
      .DESCRIPTION  Resolve o asset da release exata pela API do GitHub, valida URL,
        tamanho e SHA256 publicado pelo proprio GitHub, e troca a pasta atomicamente.
      .OUTPUTS  [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)

    if (-not $env:LOCALAPPDATA) {
        Write-Warning 'LOCALAPPDATA nao esta disponivel para a instalacao portatil.'
        return $false
    }

    $assetName = "PowerShell-$Version-win-x64.zip"
    $expectedUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/$assetName"
    try {
        $release = Invoke-PowerShellRequest `
            -Kind Rest `
            -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/tags/v$Version" `
            -Headers $script:GitHubHeaders
        $asset = @($release.assets | Where-Object { $_.name -eq $assetName }) | Select-Object -First 1
        if (-not $asset) { throw "A release v$Version nao contem $assetName." }
        if ([string]$asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw 'O asset nao publica um SHA256 valido.' }
        $expectedHash = $Matches[1].ToLowerInvariant()
        $expectedSize = [long]$asset.size
        if ($expectedSize -le 0 -or $expectedSize -gt 250MB) { throw 'O asset publica um tamanho invalido.' }
        if (-not ([string]$asset.browser_download_url).Equals($expectedUrl, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'A URL do asset oficial e inesperada.'
        }
    }
    catch {
        Write-Warning ("Nao foi possivel validar o ZIP oficial do PowerShell: {0}" -f $_.Exception.Message)
        return $false
    }

    $parentDir = [IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft')
    $destination = Join-Path $parentDir 'powershell'
    $previousDir = Join-Path $parentDir 'powershell.previous'
    $newDir = Join-Path $parentDir ('powershell.new-' + [guid]::NewGuid().ToString('N'))
    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('PowerShell-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $workDir $assetName
    $swapped = $false

    try {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        Write-Host "Baixando PowerShell $Version para o perfil do usuario..." -ForegroundColor Yellow
        Invoke-PowerShellRequest -Kind Download -Uri $expectedUrl -Headers @{ 'User-Agent' = 'SyncMaster-PowerShell-Bootstrap' } -OutFile $zipPath
        $actualSize = (Get-Item -LiteralPath $zipPath).Length
        if ($actualSize -ne $expectedSize) { throw "Tamanho do ZIP nao confere ($actualSize de $expectedSize bytes)." }
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) { throw 'SHA256 do ZIP do PowerShell nao confere.' }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $newDir -Force
        if (-not (Test-Path -LiteralPath (Join-Path $newDir 'pwsh.exe') -PathType Leaf)) {
            throw 'O ZIP do PowerShell nao contem pwsh.exe.'
        }

        if (Test-Path -LiteralPath $previousDir) { Remove-Item -LiteralPath $previousDir -Recurse -Force }
        if (Test-Path -LiteralPath $destination) { Move-Item -LiteralPath $destination -Destination $previousDir }
        Move-Item -LiteralPath $newDir -Destination $destination
        $swapped = $true
        Write-Host "PowerShell $Version instalado em $destination" -ForegroundColor Green
        return $true
    }
    catch {
        if ($swapped -and (Test-Path -LiteralPath $previousDir)) {
            if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
            Move-Item -LiteralPath $previousDir -Destination $destination
        }
        elseif (-not (Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $previousDir)) {
            Move-Item -LiteralPath $previousDir -Destination $destination
        }
        Write-Warning ("Instalacao portatil do PowerShell falhou: {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        foreach ($path in $newDir, $workDir) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Install-PowerShell7 {
    <#
      .SYNOPSIS  Instala o PowerShell 7 com cadeia de fallbacks para Windows 10/11 x64.
      .DESCRIPTION  Ordem: a) winget (se existir); b) MSI do GitHub com assinatura validada
        (precisa admin); c) ZIP oficial versionado e validado no perfil do usuario.
      .OUTPUTS  [bool] $true se o pwsh.exe está disponível ao final.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # a) winget (já trata winget ausente e exit code)
    if (Invoke-WingetInstall -PackageId 'Microsoft.PowerShell') {
        if (Find-PwshPath) { return $true }
    }

    $isAdmin = Test-IsAdmin
    $version = Get-LatestPowerShellVersion -UsePinnedFallback

    # b) MSI direto do GitHub (assinatura Authenticode validada). MSI exige admin.
    if ($isAdmin -and $version) {
        $info = Get-InstallerInfo -Version $version
        if ($info) {
            Start-PowerShellInstallation -Version $version -InstallerUrl $info.Url -InstallerPath $info.Path
            if (Find-PwshPath) { return $true }
        }
    }

    # c) ZIP oficial: sem winget, sem MSI e sem executar um bootstrap remoto mutavel.
    if ($version -and (Install-PowerShellPortable -Version $version)) { return $true }

    return [bool](Find-PwshPath)
}

function Get-InstallerInfo {
    param($Version)
    try {
        $tagUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/tags/v$Version"
        Invoke-PowerShellRequest -Kind Rest -Uri $tagUrl -Headers $script:GitHubHeaders | Out-Null
    } catch {
        Write-Warning "A versão '$Version' não foi encontrada no repositório do PowerShell."
        return $null
    }
    $osArch = (Get-CimInstance -ClassName Win32_OperatingSystem).OSArchitecture
    $platform = switch -regex ($osArch) {
        "64-bit" { "win-x64" }
        "ARM64"  { "win-arm64" }
        default  { 
            Write-Warning "Arquitetura não reconhecida ($osArch). Assumindo x64."
            "win-x64"
        }
    }
    $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-$platform.msi"
    $installerPath = "$env:TEMP\PowerShell-$Version-$platform.msi"
    return @{
        Url = $downloadUrl
        Path = $installerPath
    }
}

function Menu-AtualizacaoPowerShell {
    do {
        Clear-Host
        Write-Host "===============================" -ForegroundColor Cyan
        Write-Host "  MENU DE GESTÃO DO POWERSHELL "
        Write-Host "===============================" -ForegroundColor Cyan
        Write-Host "1. Atualizar para última versão ESTÁVEL"
        Write-Host "2. Instalar última versão PREVIEW (Beta)"
        Write-Host "3. Instalar uma versão ESPECÍFICA"
        Write-Host "4. Exibir versão atual"
        Write-Host "5. Instalar de um MSI local (offline, ex.: pendrive)"
        Write-Host "Q. Voltar ao menu principal"
        $opcao = Read-Host "`nEscolha uma opção"

        switch ($opcao) {
            '1' {
                if (-not (Invoke-WingetInstall -PackageId 'Microsoft.PowerShell')) {
                    $version = Get-LatestPowerShellVersion
                    if ($version) {
                        $installerInfo = Get-InstallerInfo -Version $version
                        if ($installerInfo) {
                           Start-PowerShellInstallation -Version $version -InstallerUrl $installerInfo.Url -InstallerPath $installerInfo.Path
                        }
                    }
                }
                Pause-Script
            }
            '2' {
                if (-not (Invoke-WingetInstall -PackageId 'Microsoft.PowerShell.Preview')) {
                    $version = Get-LatestPowerShellVersion -Preview
                    if ($version) {
                        $installerInfo = Get-InstallerInfo -Version $version
                        if ($installerInfo) {
                           Start-PowerShellInstallation -Version $version -InstallerUrl $installerInfo.Url -InstallerPath $installerInfo.Path
                        }
                    }
                }
                Pause-Script
            }
            '3' {
                $versao = Read-Host "Digite a versão exata desejada (ex: 7.4.3, 7.3.12)"
                if ($versao -match "^\d+\.\d+\.\d+.*$") {
                    $installerInfo = Get-InstallerInfo -Version $versao
                    if ($installerInfo) {
                        Start-PowerShellInstallation -Version $versao -InstallerUrl $installerInfo.Url -InstallerPath $installerInfo.Path
                    }
                } else {
                    Write-Warning "Formato de versão inválido. Use o formato X.Y.Z."
                }
                Pause-Script
            }
            '4' {
                Write-Host "Versão atual do PowerShell: $($PSVersionTable.PSVersion.ToString())" -ForegroundColor Cyan
                Pause-Script
            }
            '5' {
                $msi = Read-Host "Caminho completo do MSI (ex: E:\PowerShell-7.5.2-win-x64.msi)"
                if ([string]::IsNullOrWhiteSpace($msi)) {
                    Write-Warning "Nenhum caminho informado."
                } else {
                    # Mesma validação de assinatura do caminho online — MSI de pendrive não é confiável por si só
                    Install-PowerShellFromMsi -Path $msi.Trim('"') | Out-Null
                }
                Pause-Script
            }
            'Q' { break }
            default {
                Write-Host "Opção inválida, tente novamente." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    } while ($opcao.ToUpper() -ne 'Q')
}

Export-ModuleMember -Function Get-LatestPowerShellVersion, Get-VersionFromReleaseUrl, Start-PowerShellInstallation, Install-PowerShellFromMsi, Install-PowerShellPortable, Get-InstallerInfo, Invoke-WingetInstall, Find-PwshPath, Install-PowerShell7, Menu-AtualizacaoPowerShell
