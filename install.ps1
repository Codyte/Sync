#Requires -Version 5.1
<#
.SYNOPSIS
    Instala ou atualiza o Sync Master no perfil do usuario.
.DESCRIPTION
    Baixa o ZIP da branch master, valida a estrutura, substitui somente os arquivos
    do aplicativo em %LOCALAPPDATA%\SyncMaster\App e inicia o launcher. Logs e dados
    ficam fora dessa pasta e sao preservados.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ArchivePath,
    [string]$CommitId,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
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
if (-not $ArchivePath -and -not $remoteCommit) {
    try {
        $remoteCommit = (Invoke-RestMethod -Uri 'https://api.github.com/repos/Codyte/Sync/commits/master' -UseBasicParsing).sha
    } catch {
        Write-Warning 'Nao foi possivel verificar a versao; baixando a versao atual.'
    }
}
if ($remoteCommit -and $remoteCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'CommitId invalido.' }

$installComplete = Test-Path -LiteralPath $installDir -PathType Container
foreach ($item in $requiredItems) {
    if (-not (Test-Path -LiteralPath (Join-Path $installDir $item))) { $installComplete = $false; break }
}
$localCommit = if (Test-Path -LiteralPath $markerPath) { (Get-Content -Raw -LiteralPath $markerPath).Trim() }
if ($remoteCommit -and $installComplete -and $localCommit -eq $remoteCommit) {
    Write-Host 'Sync Master ja esta atualizado. Abrindo...' -ForegroundColor Green
    if (-not $NoLaunch) { Start-Process -FilePath (Join-Path $installDir 'Sync Master.cmd') -WorkingDirectory $installDir }
    return
}

$workDir = Join-Path ([IO.Path]::GetTempPath()) ('SyncMaster-' + [guid]::NewGuid().ToString('N'))
$zipPath = if ($ArchivePath) { (Resolve-Path -LiteralPath $ArchivePath).Path } else { Join-Path $workDir 'Sync.zip' }
$newDir = Join-Path $appRoot ('App.new-' + [guid]::NewGuid().ToString('N'))
$oldDir = Join-Path $appRoot ('App.old-' + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    if (-not $ArchivePath) {
        Write-Host 'Baixando Sync Master do GitHub...' -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $archiveUrl = if ($remoteCommit) { "https://github.com/Codyte/Sync/archive/$remoteCommit.zip" } else { 'https://github.com/Codyte/Sync/archive/refs/heads/master.zip' }
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing
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
    if ($remoteCommit) { Set-Content -LiteralPath (Join-Path $newDir '.syncmaster-commit') -Value $remoteCommit -Encoding ASCII }
    if (Test-Path -LiteralPath $installDir) { Move-Item -LiteralPath $installDir -Destination $oldDir }
    Move-Item -LiteralPath $newDir -Destination $installDir
    if (Test-Path -LiteralPath $oldDir) { Remove-Item -LiteralPath $oldDir -Recurse -Force }

    Write-Host "Sync Master instalado em: $installDir" -ForegroundColor Green
    if (-not $NoLaunch) {
        Start-Process -FilePath (Join-Path $installDir 'Sync Master.cmd') -WorkingDirectory $installDir
    }
}
catch {
    if (-not (Test-Path -LiteralPath $installDir) -and (Test-Path -LiteralPath $oldDir)) {
        Move-Item -LiteralPath $oldDir -Destination $installDir
    }
    throw
}
finally {
    foreach ($path in $newDir, $oldDir, $workDir) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
