#Requires -Version 5.1
<#
.SYNOPSIS
    Instala ou atualiza o Sync Master no perfil do usuario.
.DESCRIPTION
    Prefere a release estavel SyncMaster.zip e valida o SHA256 publicado pela API do
    GitHub. Enquanto nenhuma release existir, usa o ZIP de um commit exato da master.
    Requer Windows 10/11 x64. Repete falhas transitorias, substitui somente os
    arquivos do aplicativo, preserva logs/dados e conserva a versao anterior.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ArchivePath,
    [string]$CommitId,
    [string]$ExpectedSha256,
    [ValidateSet('Stable', 'Master')]
    [string]$Channel = 'Stable',
    [switch]$NoLaunch
)

function Invoke-SyncMasterRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Rest', 'Download')][string]$Kind,
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers,
        [string]$OutFile,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $request = @{
                Uri             = $Uri
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
                TimeoutSec      = 60
            }
            if ($Headers) { $request.Headers = $Headers }
            if ($Kind -eq 'Download') {
                if ([string]::IsNullOrWhiteSpace($OutFile)) { throw 'OutFile e obrigatorio para download.' }
                $request.OutFile = $OutFile
                Invoke-WebRequest @request | Out-Null
                return
            }
            return Invoke-RestMethod @request
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

$ErrorActionPreference = 'Stop'
$maxArchiveBytes = 250MB
if ($env:OS -ne 'Windows_NT') { throw 'Este instalador requer Windows.' }
if ([Environment]::OSVersion.Version.Major -lt 10) { throw 'Este instalador requer Windows 10 ou 11.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Este instalador requer Windows x64.' }
$base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:USERPROFILE }
if (-not $base) { throw 'LOCALAPPDATA e USERPROFILE nao estao disponiveis.' }

$appRoot = Join-Path $base 'SyncMaster'
$installDir = Join-Path $appRoot 'App'
$markerPath = Join-Path $installDir '.syncmaster-commit'
$requiredItems = @('Sync Master.cmd', 'Sync_Master.ps1', 'SyncMaster.psd1', 'modules')
# Em `irm ... | iex`, $PSCmdlet pode ser nulo; em chamada direta, preserva -WhatIf/-Confirm.
if ($WhatIfPreference) {
    Write-Host "What if: instalar ou atualizar o Sync Master em '$installDir'."
    return
}
if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($installDir, 'Instalar ou atualizar o Sync Master')) { return }

$remoteCommit = $CommitId
if ($remoteCommit -and $remoteCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'CommitId invalido.' }
$expectedHash = if ($ExpectedSha256) { $ExpectedSha256.Trim().ToLowerInvariant() } else { $null }
if ($expectedHash -and $expectedHash -notmatch '^[0-9a-f]{64}$') { throw 'ExpectedSha256 invalido.' }

$releaseTag = $null
$downloadUrl = $null
$expectedSize = $null
$apiHeaders = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'SyncMaster-Installer'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $ArchivePath -and -not $remoteCommit -and $Channel -eq 'Stable') {
    try {
        $release = Invoke-SyncMasterRequest -Kind Rest -Uri 'https://api.github.com/repos/Codyte/Sync/releases/latest' -Headers $apiHeaders
        if ($release.draft -or $release.prerelease) { throw 'A release mais recente nao e estavel.' }
        $asset = @($release.assets | Where-Object { $_.name -eq 'SyncMaster.zip' }) | Select-Object -First 1
        if (-not $asset) { throw 'A release nao contem o asset SyncMaster.zip.' }
        if ([string]$asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw 'A release nao publica um digest SHA256 valido.' }
        $assetHash = $Matches[1].ToLowerInvariant()
        $expectedSize = [long]$asset.size
        if ($expectedSize -le 0 -or $expectedSize -gt $maxArchiveBytes) { throw 'A release publica um tamanho de pacote invalido.' }
        if ([string]::IsNullOrWhiteSpace([string]$asset.browser_download_url)) { throw 'A release nao publica uma URL de download.' }
        if ([string]$release.tag_name -notmatch '^v?[0-9][0-9A-Za-z._-]{0,63}$') { throw 'A release possui uma tag invalida.' }

        $releaseTag = [string]$release.tag_name
        $downloadUrl = [string]$asset.browser_download_url
        $expectedUrl = "https://github.com/Codyte/Sync/releases/download/$releaseTag/SyncMaster.zip"
        if (-not $downloadUrl.Equals($expectedUrl, [StringComparison]::OrdinalIgnoreCase)) { throw 'A release publicou uma URL de asset inesperada.' }
        if ($expectedHash -and $expectedHash -ne $assetHash) { throw 'O SHA256 fixado nao corresponde ao digest da release.' }
        $expectedHash = $assetHash
        if ($release.PSObject.Properties['immutable'] -and -not $release.immutable) {
            Write-Warning 'A release ainda nao esta marcada como imutavel no GitHub.'
        }
    } catch {
        $releaseError = $_
        $statusCode = $null
        try { $statusCode = [int]$releaseError.Exception.Response.StatusCode } catch { $statusCode = $null }
        if ($statusCode -ne 404) { throw "Falha ao consultar a release estavel: $($releaseError.Exception.Message)" }
        Write-Warning 'Nenhuma release estavel publicada; usando temporariamente um commit exato da master.'
    }
}

if (-not $ArchivePath -and -not $downloadUrl -and -not $remoteCommit) {
    try {
        $remoteCommit = (Invoke-SyncMasterRequest -Kind Rest -Uri 'https://api.github.com/repos/Codyte/Sync/commits/master' -Headers $apiHeaders).sha
    } catch {
        throw "Nao foi possivel resolver o commit atual da master: $($_.Exception.Message)"
    }
    if ($remoteCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'O GitHub retornou um commit invalido.' }
}

$remoteMarker = if ($releaseTag) { "release:$releaseTag" } else { $remoteCommit }

$installComplete = Test-Path -LiteralPath $installDir -PathType Container
foreach ($item in $requiredItems) {
    if (-not (Test-Path -LiteralPath (Join-Path $installDir $item))) { $installComplete = $false; break }
}
$localCommit = if (Test-Path -LiteralPath $markerPath) { (Get-Content -Raw -LiteralPath $markerPath).Trim() }
if ($remoteMarker -and $installComplete -and $localCommit -eq $remoteMarker) {
    Write-Host 'Sync Master ja esta atualizado. Abrindo...' -ForegroundColor Green
    if (-not $NoLaunch) { Start-Process -FilePath (Join-Path $installDir 'Sync Master.cmd') -WorkingDirectory $installDir }
    return
}

$workDir = Join-Path ([IO.Path]::GetTempPath()) ('SyncMaster-' + [guid]::NewGuid().ToString('N'))
$zipPath = if ($ArchivePath) { (Resolve-Path -LiteralPath $ArchivePath).Path } else { Join-Path $workDir 'Sync.zip' }
$newDir = Join-Path $appRoot ('App.new-' + [guid]::NewGuid().ToString('N'))
$previousDir = Join-Path $appRoot 'App.previous'
$swapped = $false

try {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    if (-not $ArchivePath) {
        Write-Host 'Baixando Sync Master do GitHub...' -ForegroundColor Cyan
        $archiveUrl = if ($downloadUrl) { $downloadUrl } else { "https://github.com/Codyte/Sync/archive/$remoteCommit.zip" }
        Invoke-SyncMasterRequest -Kind Download -Uri $archiveUrl -Headers @{ 'User-Agent' = 'SyncMaster-Installer' } -OutFile $zipPath
    }

    $archiveLength = (Get-Item -LiteralPath $zipPath).Length
    if ($archiveLength -le 0 -or $archiveLength -gt $maxArchiveBytes) { throw 'O pacote esta vazio ou excede o limite de 250 MB.' }
    if ($expectedSize -and $archiveLength -ne $expectedSize) {
        throw "Tamanho do pacote nao confere. Esperado: $expectedSize; recebido: $archiveLength."
    }

    if ($expectedHash) {
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) { throw "SHA256 do pacote nao confere. Esperado: $expectedHash; recebido: $actualHash." }
    }

    $extractDir = Join-Path $workDir 'src'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $sourceDir = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
    if (-not $sourceDir) { throw 'O pacote baixado nao contem uma pasta raiz.' }

    foreach ($required in $requiredItems) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceDir.FullName $required))) {
            throw "Pacote invalido: item ausente ($required)."
        }
    }

    New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
    Copy-Item -LiteralPath $sourceDir.FullName -Destination $newDir -Recurse
    if ($remoteMarker) { Set-Content -LiteralPath (Join-Path $newDir '.syncmaster-commit') -Value $remoteMarker -Encoding ASCII }
    if (Test-Path -LiteralPath $previousDir) { Remove-Item -LiteralPath $previousDir -Recurse -Force }
    if (Test-Path -LiteralPath $installDir) { Move-Item -LiteralPath $installDir -Destination $previousDir }
    Move-Item -LiteralPath $newDir -Destination $installDir
    $swapped = $true

    Write-Host "Sync Master instalado em: $installDir" -ForegroundColor Green
    if (-not $NoLaunch) {
        Start-Process -FilePath (Join-Path $installDir 'Sync Master.cmd') -WorkingDirectory $installDir
    }
}
catch {
    if ($swapped -and (Test-Path -LiteralPath $previousDir)) {
        if (Test-Path -LiteralPath $installDir) { Remove-Item -LiteralPath $installDir -Recurse -Force }
        Move-Item -LiteralPath $previousDir -Destination $installDir
    }
    elseif (-not (Test-Path -LiteralPath $installDir) -and (Test-Path -LiteralPath $previousDir)) {
        Move-Item -LiteralPath $previousDir -Destination $installDir
    }
    throw
}
finally {
    foreach ($path in $newDir, $workDir) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
