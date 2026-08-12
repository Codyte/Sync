<#
    Backup.psm1 — backup ZIP e clonagem de disco.
    Extraido do monolito legado (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

# ───────────────────────── Nucleo (Fase B) ─────────────────────────
# Logica sem UI (sem Write-Host/Read-Host/Pause/Out-GridView). Get-ZipBackupPath e' pura;
# Invoke-Zip* fazem I/O mas retornam objeto-resultado (Sucesso/Mensagem) e nao prompts.
# Os presenters Criar-/Restaurar-BackupZIP consomem estas funcoes.

function Get-ZipBackupPath {
    <#
      .SYNOPSIS  Monta o caminho do .zip de backup. Funcao PURA (sem I/O).
      .DESCRIPTION  Padrao: Backup_{nome-da-pasta}_{yyyyMMdd_HHmmss}.zip dentro de DestinoDir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$OrigemPath,
        [Parameter(Mandatory=$true)][string]$DestinoDir,
        [datetime]$Timestamp = (Get-Date)
    )
    $nome = "Backup_{0}_{1}.zip" -f (Split-Path $OrigemPath -Leaf), $Timestamp.ToString('yyyyMMdd_HHmmss')
    # [IO.Path]::Combine, nao Join-Path: Join-Path valida o drive contra os PSDrives da
    # sessao e lanca DriveNotFoundException p/ unidade inexistente — quebra a pureza.
    return [IO.Path]::Combine($DestinoDir, $nome)
}

function Invoke-ZipBackup {
    <#
      .SYNOPSIS  Compacta OrigemDir em DestinoZip. Sem UI; devolve objeto-resultado.
      .OUTPUTS   PSCustomObject { Sucesso, Caminho, Mensagem }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$OrigemDir,
        [Parameter(Mandatory=$true)][string]$DestinoZip
    )
    try {
        if (-not (Test-Path -LiteralPath $OrigemDir -PathType Container)) { throw "Pasta de origem nao encontrada: $OrigemDir" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($OrigemDir, $DestinoZip)
        return [pscustomobject]@{ Sucesso = $true;  Caminho = $DestinoZip; Mensagem = "Backup ZIP criado: $DestinoZip" }
    } catch {
        return [pscustomobject]@{ Sucesso = $false; Caminho = $DestinoZip; Mensagem = $_.Exception.Message }
    }
}

function Invoke-ZipRestore {
    <#
      .SYNOPSIS  Extrai ZipPath em DestinoDir. Sem UI; devolve objeto-resultado.
      .DESCRIPTION  -Sobrescrever usa o overload overwrite (so PS7/.NET Core); em PS5 ou sem
        o switch cai no extract padrao (lanca se arquivo ja existe).
      .OUTPUTS   PSCustomObject { Sucesso, Destino, Mensagem }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$DestinoDir,
        [switch]$Sobrescrever
    )
    try {
        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "Arquivo ZIP nao encontrado: $ZipPath" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if ($Sobrescrever -and $PSVersionTable.PSVersion.Major -ge 7) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinoDir, $true)
        } else {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinoDir)
        }
        return [pscustomobject]@{ Sucesso = $true;  Destino = $DestinoDir; Mensagem = "Restaurado para: $DestinoDir" }
    } catch {
        return [pscustomobject]@{ Sucesso = $false; Destino = $DestinoDir; Mensagem = $_.Exception.Message }
    }
}

function Criar-BackupZIP {
    $origemObj = Selecionar-DiretorioDaLista -Titulo "Selecione a pasta para BACKUP (ZIP)"
    if (-not $origemObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    $origem = $origemObj.Caminho
    # Backups vao para o data dir do usuario (portavel), nao ao lado do script.
    $destinoZIP = Get-ZipBackupPath -OrigemPath $origem -DestinoDir (Get-SyncMasterDataDir -SubPasta 'Backups')
    $res = Invoke-ZipBackup -OrigemDir $origem -DestinoZip $destinoZIP
    if ($res.Sucesso) {
        Write-Host "Backup ZIP criado com sucesso: $($res.Caminho)" -ForegroundColor Green
        Registrar-Log "Backup ZIP de $origem para $destinoZIP"
    } else {
        Write-Warning "Erro ao criar o backup ZIP: $($res.Mensagem)"
    }
    Pause-Script
}

function Restaurar-BackupZIP {
    # Lista os ZIPs do data dir de backups (mesmo local onde Criar-BackupZIP grava).
    $bkpDir = Get-SyncMasterDataDir -SubPasta 'Backups'
    $zips = @(Get-ChildItem -Path $bkpDir -Filter *.zip -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($zips.Count -eq 0) { Write-Host "Nenhum ZIP encontrado em: $bkpDir."; Pause-Script; return }
    # Out-GridView nao existe em Server Core / hosts sem GUI: cai numa lista numerada.
    $zip = $null
    try {
        $zip = $zips | Out-GridView -Title "Escolha o arquivo ZIP para restaurar" -PassThru
    } catch {
        Write-Verbose "Out-GridView indisponivel: $($_.Exception.Message)"
        Write-Host "--- BACKUPS DISPONÍVEIS ---" -ForegroundColor Cyan
        for ($i = 0; $i -lt $zips.Count; $i++) {
            Write-Host ('{0,3}. {1}  ({2:yyyy-MM-dd HH:mm})' -f ($i+1), $zips[$i].Name, $zips[$i].LastWriteTime)
        }
        $sel = Read-Host "Número do ZIP a restaurar (Enter cancela)"
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $zips.Count) { $zip = $zips[[int]$sel - 1] }
    }
    if (-not $zip) { Write-Host "Nenhum ZIP selecionado (procurados em: $bkpDir)."; Pause-Script; return }
    $destinoObj = Selecionar-DiretorioDaLista -Titulo "Selecione o DESTINO para RESTAURAR backup ZIP"
    if (-not $destinoObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    $destino = $destinoObj.Caminho
    # -Sobrescrever preserva o comportamento atual (overwrite no PS7); o nucleo cuida do fallback PS5.
    $res = Invoke-ZipRestore -ZipPath $zip.FullName -DestinoDir $destino -Sobrescrever
    if ($res.Sucesso) {
        Write-Host "Backup ZIP restaurado com sucesso para: $destino" -ForegroundColor Green
        Registrar-Log "Restaurado ZIP $($zip.FullName) para $destino"
    } else {
        Write-Warning "Erro ao restaurar ZIP: $($res.Mensagem)"
    }
    Pause-Script
}

Export-ModuleMember -Function Get-ZipBackupPath, Invoke-ZipBackup, Invoke-ZipRestore, Criar-BackupZIP, Restaurar-BackupZIP
