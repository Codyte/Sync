<#
    Core.psm1 — utilitarios base do Sync Master, sem dependencias de dominio.
    Primeiro modulo extraido do monolito legado (Fase 5 do refator).

    Estado GRAVAVEL (logs, backups, config) mora num data dir do usuario, NAO ao lado
    do script — assim o Sync Master roda de qualquer local e em qualquer PC Windows,
    inclusive de pastas somente-leitura (Program Files, rede, midia). Ver Get-SyncMasterDataDir.
#>

function Get-SyncMasterDataDir {
    <#
      .SYNOPSIS  Retorna (criando) o diretorio GRAVAVEL de dados do Sync Master.
      .DESCRIPTION  Portabilidade: o estado nao acompanha o script. Base resolvida por:
        1) $env:SYNCMASTER_DATA_DIR (override explicito);
        2) %LOCALAPPDATA%\SyncMaster (padrao por-usuario);
        3) %USERPROFILE%\SyncMaster (fallback se LOCALAPPDATA ausente).
      .PARAMETER SubPasta  Subpasta opcional (ex.: 'Logs', 'Backups'); tambem e' criada.
    #>
    param([string]$SubPasta)
    $base = if ($env:SYNCMASTER_DATA_DIR)   { $env:SYNCMASTER_DATA_DIR }
            elseif ($env:LOCALAPPDATA)      { Join-Path $env:LOCALAPPDATA 'SyncMaster' }
            else                            { Join-Path $env:USERPROFILE  'SyncMaster' }
    $dir = if ($SubPasta) { Join-Path $base $SubPasta } else { $base }
    if (Test-Path -LiteralPath $dir -ErrorAction Stop) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container -ErrorAction Stop)) {
            throw "O caminho de dados existe, mas nao e um diretorio: $dir"
        }
    } else {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    }
    return $dir
}

$script:LogsDir = Get-SyncMasterDataDir -SubPasta 'Logs'

# Pausa o script ate o usuario pressionar uma tecla.
function Pause-Script {
    Write-Host "Pressione qualquer tecla para voltar ao menu..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Confirmacao S/N. Retorna $true se o usuario digitar S/s.
function Confirm-Action {
    param ([string]$Prompt = "Tem certeza que deseja continuar?")
    $resposta = Read-Host -Prompt "$Prompt (S/N)"
    return $resposta -match '^[Ss]$'
}

# Acrescenta uma linha ao log diario (Logs/log_AAAA-MM-DD.txt).
# Best-effort (igual ao transcript): logging nunca pode derrubar a operacao do menu.
# Uma falha de Add-Content (arquivo travado por escrita concorrente, disco cheio,
# pasta somente-leitura) era propagada e abortava o caller. UTF8 preserva os acentos.
function Registrar-Log($msg) {
    try {
        $log = Join-Path $script:LogsDir ("log_" + (Get-Date -Format 'yyyy-MM-dd') + ".txt")
        $linha = (Get-Date -Format "HH:mm:ss") + " - $msg"
        Add-Content -Path $log -Value $linha -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Verbose "Registrar-Log falhou: $($_.Exception.Message)"
    }
}

# Transcript de SESSAO: captura TUDO que aparece no console (menus, saidas, erros)
# num arquivo cronologico no data dir (Logs/sessao_*.log). Complementa o log diario
# estruturado (Registrar-Log). Best-effort: nunca derruba o script se falhar.
$script:SessionTranscript = $null
function Start-SyncMasterLog {
    [CmdletBinding()]
    param()
    if ($script:SessionTranscript) { return $script:SessionTranscript }  # ja iniciado
    $path = Join-Path (Get-SyncMasterDataDir -SubPasta 'Logs') ("sessao_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
    try {
        Start-Transcript -Path $path -Append -ErrorAction Stop | Out-Null
        $script:SessionTranscript = $path
        Registrar-Log "=== Sessao iniciada (transcript: $path) ==="
        return $path
    } catch {
        Write-Verbose "Transcript de sessao nao iniciado: $($_.Exception.Message)"
        return $null
    }
}

# Encerra o transcript de sessao (footer). Idempotente; tolerante a falha.
function Stop-SyncMasterLog {
    [CmdletBinding()]
    param()
    if (-not $script:SessionTranscript) { return }
    Registrar-Log "=== Sessao encerrada ==="
    try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { Write-Verbose $_.Exception.Message }
    $script:SessionTranscript = $null
}

# Abre o log mais recente no Notepad.
function Visualizar-Logs {
    $logFile = Get-ChildItem -Path $script:LogsDir -Filter *.txt |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($logFile) {
        notepad $logFile.FullName
    } else {
        Write-Host "Nenhum log encontrado." -ForegroundColor Yellow
        Pause-Script
    }
}

# Abre o menu interativo do Sync Master a partir do modulo instalado. Acha o launcher
# Sync_Master.ps1 um nivel acima de modules\ (vale no repo e quando instalado como
# modulo: Modules\SyncMaster\Sync_Master.ps1 + Modules\SyncMaster\modules\Core.psm1).
# Permite digitar 'Start-SyncMaster' de qualquer lugar apos a instalacao.
function Start-SyncMaster {
    # Sem [CmdletBinding()]: deixa $args capturar parametros extras p/ repassar ao launcher
    # (ex.: Start-SyncMaster -Acao Sincronizar -Origem X -Destino Y).
    $entry = Join-Path (Split-Path $PSScriptRoot -Parent) 'Sync_Master.ps1'
    if (-not (Test-Path $entry)) {
        Write-Error "Launcher nao encontrado: $entry"
        return
    }
    & $entry @args
}

# Garante que um diretorio exista (idempotente).
function Ensure-Dir {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -ErrorAction Stop) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)) {
            throw "O caminho existe, mas nao e um diretorio: $Path"
        }
        return
    }
    New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
}

# Retorna $true se a sessao atual e elevada (Administrador).
function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Aborta (throw) se nao estiver elevado. Helper transversal usado por varios modulos.
function Require-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Warning "Execute como Administrador."
        Pause-Script
        throw "Sem privilégios de administrador."
    }
}

Export-ModuleMember -Function Get-SyncMasterDataDir, Start-SyncMaster, Start-SyncMasterLog, Stop-SyncMasterLog, Pause-Script, Confirm-Action, Registrar-Log, Visualizar-Logs, Ensure-Dir, Test-IsAdmin, Require-Admin
