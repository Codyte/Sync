# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L55    Salvar-Diretorios
#   L66    Menu-GerenciamentoDiretorios
#   L130   Selecionar-DiretorioDaLista
#   L168   ObterCaminhoPasta
#   L189   Iniciar-Sincronizacao
#   L269   Resolve-ShareToDiskInfoV2
#   L328   VerificarEspacoEmDiscoV2
#   L372   Get-TamanhoPastaBytesV2
#   L379   Comparar-EspacoVsOrigemV2
#   L419   Get-RobocopyArgs
#   L463   Get-RobocopyStatus
#   L481   Resolve-RobocopyTuning
#   L513   ConvertTo-TamanhoLegivel
#   L524   Format-RobocopyResumo
#   L575   Get-ExclusoesPerfil
#   L598   Test-OrigemEhPerfil
#   L617   Measure-ArvoreRapido
#   L639   Test-ParOrigemDestino
#   L677   Show-RobocopyResultado
#   L703   Start-RobocopyUnilateralSeguro
#   L769   Start-RobocopyEspelho
#   L831   Iniciar-SincronizacaoV2
#   L836   Agendar-TarefaSincronizacao
# ======================= END NAV INDEX =======================

<#
    Sync.psm1 — engine de sincronizacao (robocopy) + diretorios salvos do Sync Master.
    Extraido do monolito legado (Fase 5). Depende de Core.psm1.
    Estado dos diretorios salvos (diretorios.json) mora no data dir do usuario
    (Get-SyncMasterDataDir) para o script ser portatil; migra o legado da raiz uma vez.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

$script:diretoriosConfigFile = Join-Path (Get-SyncMasterDataDir) 'diretorios.json'
# Migracao 1x: versoes antigas gravavam diretorios.json na raiz do projeto. Se o novo
# local ainda nao tem o arquivo mas o legado existe, traz os diretorios salvos do usuario.
$legadoConfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'diretorios.json'
if (-not (Test-Path $script:diretoriosConfigFile) -and (Test-Path $legadoConfig)) {
    try { Copy-Item -LiteralPath $legadoConfig -Destination $script:diretoriosConfigFile -Force } catch { Write-Verbose $_.Exception.Message }
}
if (Test-Path $script:diretoriosConfigFile) {
    try {
        $script:diretoriosSalvos = Get-Content $script:diretoriosConfigFile -Raw | ConvertFrom-Json
        if ($null -ne $script:diretoriosSalvos -and $script:diretoriosSalvos -isnot [array]) { $script:diretoriosSalvos = @($script:diretoriosSalvos) }
    } catch {
        Write-Warning "Arquivo de configuracao de diretorios corrompido."
        $script:diretoriosSalvos = @()
    }
} else {
    $script:diretoriosSalvos = @()
}
if ($null -eq $script:diretoriosSalvos) { $script:diretoriosSalvos = @() }
function Salvar-Diretorios {
    try {
        # UTF8: sem isto o Set-Content do PS5 grava ANSI e corrompe acentos em Nome/Caminho.
        $script:diretoriosSalvos | ConvertTo-Json -Depth 5 | Set-Content -Path $diretoriosConfigFile -Encoding UTF8
        return $true
    } catch {
        Write-Warning "ERRO: Não foi possível salvar o arquivo de configuração. $($_.Exception.Message)"
        return $false
    }
}

function Menu-GerenciamentoDiretorios {
    do {
        Clear-Host
        Write-Host "--- GERENCIAMENTO DE DIRETÓRIOS SALVOS ---" -ForegroundColor Cyan
        
        if ($diretoriosSalvos.Count -eq 0) {
            Write-Host "Nenhum diretório salvo." -ForegroundColor Yellow
        } else {
            for ($i = 0; $i -lt $diretoriosSalvos.Count; $i++) {
                Write-Host ('{0,3}. {1,-25} -> {2}' -f ($i+1), $diretoriosSalvos[$i].Nome, $diretoriosSalvos[$i].Caminho)
            }
        }
        
        Write-Host "---------------------------------------------"
        Write-Host "A - Adicionar novo diretório"
        Write-Host "R - Remover um diretório"
        Write-Host "Q - Voltar ao menu principal"
        
        $opcao = Read-Host "Sua escolha"
        
        switch ($opcao.ToUpper()) {
            'A' {
                $nome = Read-Host "Digite um nome/apelido para este diretório (ex: Servidor Principal)"
                if ([string]::IsNullOrWhiteSpace($nome)) { Write-Warning "O nome não pode ser vazio."; Pause-Script; continue }
                
                $caminho = ObterCaminhoPasta -titulo "Selecione a pasta para '$nome'"
                
                if (-not $caminho) {
                    Write-Host "Seleção de pasta cancelada ou falhou. Retornando ao menu." -ForegroundColor Yellow
                    Pause-Script
                    continue 
                }

                $novoDiretorio = [pscustomobject]@{
                    Nome = $nome
                    Caminho = $caminho
                }
                $script:diretoriosSalvos += $novoDiretorio
                if (Salvar-Diretorios) { Write-Host "Diretório '$nome' salvo com sucesso!" -ForegroundColor Green }
                Pause-Script
            }
            'R' {
                if ($diretoriosSalvos.Count -eq 0) { Write-Warning "Não há diretórios para remover."; Pause-Script; continue }
                $numStr = Read-Host "Digite o NÚMERO do diretório a ser removido"
                if ($numStr -match '^\d+$' -and [int]$numStr -ge 1 -and [int]$numStr -le $diretoriosSalvos.Count) {
                    $index = [int]$numStr - 1
                    $nomeRemovido = $diretoriosSalvos[$index].Nome
                    if (Confirm-Action "Tem certeza que deseja remover '$nomeRemovido'?") {
                        $tempList = [System.Collections.Generic.List[object]]::new($diretoriosSalvos)
                        $tempList.RemoveAt($index)
                        $script:diretoriosSalvos = $tempList.ToArray()
                        if (Salvar-Diretorios) { Write-Host "Diretório '$nomeRemovido' removido com sucesso!" -ForegroundColor Green }
                    }
                } else {
                    Write-Warning "Número inválido."
                }
                Pause-Script
            }
            'Q' { return }
            default { Write-Warning "Opção inválida."; Pause-Script }
        }
    } while ($true)
}

function Selecionar-DiretorioDaLista {
    param([string]$Titulo = "Selecione um diretório")
    
    Clear-Host
    Write-Host "--- $Titulo ---" -ForegroundColor Cyan
    
    if ($diretoriosSalvos.Count -eq 0) {
        Write-Host "Nenhum diretório salvo na biblioteca. Indo para seleção manual." -ForegroundColor Yellow
        Pause-Script
        $caminhoManual = ObterCaminhoPasta -titulo "Seleção Manual para $Titulo"
        if ($caminhoManual) {
            return [pscustomobject]@{ Nome = "Manual"; Caminho = $caminhoManual }
        }
        return $null
    }

    for ($i = 0; $i -lt $diretoriosSalvos.Count; $i++) {
        Write-Host ('{0,3}. {1}' -f ($i+1), $diretoriosSalvos[$i].Nome)
    }
    Write-Host "---------------------------------------------"
    Write-Host "M - Selecionar um caminho diferente (Manual)"
    Write-Host "C - Cancelar"
    
    $escolha = Read-Host "Escolha um diretório da lista ou uma opção"
    
    if ($escolha -match '^\d+$' -and [int]$escolha -ge 1 -and [int]$escolha -le $diretoriosSalvos.Count) {
        $index = [int]$escolha - 1
        return $diretoriosSalvos[$index]
    } elseif ($escolha -match '^[Mm]$') {
        $caminhoManual = ObterCaminhoPasta -titulo "Seleção Manual para $Titulo"
        if ($caminhoManual) {
            return [pscustomobject]@{ Nome = "Manual"; Caminho = $caminhoManual }
        }
    }
    
    return $null # Cancelado
}

function ObterCaminhoPasta {
    param([string]$titulo = "Selecione uma pasta")
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = $titulo
        $folderBrowser.ShowNewFolderButton = $true
        if ($folderBrowser.ShowDialog() -eq "OK") { return $folderBrowser.SelectedPath } 
        else { Write-Warning "Seleção de pasta cancelada."; return $null }
    }
    catch {
        Write-Warning "Não foi possível carregar o seletor de pastas gráfico. Usando entrada manual."
        do {
            $caminho = Read-Host -Prompt "Digite o caminho completo para a pasta de '$titulo' (ou Enter para cancelar)"
            if ([string]::IsNullOrWhiteSpace($caminho)) { return $null }
            if (Test-Path -Path $caminho -PathType Container) { return $caminho }
            Write-Warning "Caminho inválido ou não é um diretório. Tente novamente."
        } while ($true)
    }
}

function Iniciar-Sincronizacao {
<#
.SYNOPSIS
    Menu unificado de sincronizacao: junta os modos antes separados em "1" e "1.1".
.DESCRIPTION
    Seleciona origem/destino e oferece, num so lugar, todos os modos com a engine segura
    (checagem de espaco, log e dry-run): SIMULAR, copiar unilateral segura, copiar unilateral
    COMPLETA (/COPYALL, preserva ACL/owner), ESPELHAR (/MIR, destrutivo) e ESTIMAR espaco.
#>
    Clear-Host
    Write-Host "--- SINCRONIZAÇÃO DE ARQUIVOS ---" -ForegroundColor Cyan

    $origemObj = Selecionar-DiretorioDaLista -Titulo "Selecione a ORIGEM da sincronização"
    if (-not $origemObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    $destinoObj = Selecionar-DiretorioDaLista -Titulo "Selecione o DESTINO da sincronização"
    if (-not $destinoObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    $origem  = $origemObj.Caminho
    $destino = $destinoObj.Caminho

    Clear-Host
    Write-Host "ORIGEM : $origem"  -ForegroundColor Green
    Write-Host "DESTINO: $destino" -ForegroundColor Green
    Write-Host ""
    Write-Host "Escolha a operação:" -ForegroundColor Cyan
    Write-Host "  1) SIMULAR (dry-run) - não copia, só lista o que faria"
    Write-Host "  2) COPIAR unilateral SEGURA (dados/tempo; sem permissões)"
    Write-Host "  3) COPIAR unilateral COMPLETA (/COPYALL: preserva ACL/owner - entre servidores)"
    Write-Host "  4) ESPELHAR (/MIR) - destino vira cópia EXATA da origem (APAGA extras no destino)" -ForegroundColor Red
    Write-Host "  5) ESTIMAR tamanho x espaço (relatório)"
    Write-Host "  C) Cancelar"
    $opt = Read-Host "Sua opção"

    switch ($opt.ToUpper()) {
        '1' {
            Start-RobocopyUnilateralSeguro -Origem $origem -Destino $destino -Simular
            Pause-Script
        }
        '2' {
            if (Confirm-Action -Prompt "Confirma cópia unilateral SEGURA?") {
                Start-RobocopyUnilateralSeguro -Origem $origem -Destino $destino
            }
            Pause-Script
        }
        '3' {
            if (Confirm-Action -Prompt "Confirma cópia unilateral COMPLETA (/COPYALL)?") {
                Start-RobocopyUnilateralSeguro -Origem $origem -Destino $destino -PreservarTudo
            }
            Pause-Script
        }
        '4' {
            Write-Warning "ESPELHO /MIR é DESTRUTIVO: apaga no destino tudo que não existe na origem."
            if (Confirm-Action -Prompt "Deseja SIMULAR primeiro (dry-run)?") {
                Start-RobocopyEspelho -Origem $origem -Destino $destino -Simular
                if (-not (Confirm-Action -Prompt "Revisou a simulação. Executar o espelho DE VERDADE agora?")) {
                    Write-Host "Cancelado."; Pause-Script; return
                }
            }
            if (Confirm-Action -Prompt "CONFIRMAÇÃO FINAL: espelhar (pode APAGAR arquivos no destino)?") {
                Start-RobocopyEspelho -Origem $origem -Destino $destino
            } else { Write-Host "Cancelado." }
            Pause-Script
        }
        '5' {
            $cmp = Comparar-EspacoVsOrigemV2 -Origem $origem -Destino $destino
            Write-Host "`n--- RELATÓRIO ---" -ForegroundColor Cyan
            Write-Host ("Origem........: {0:N2} GB" -f $cmp.OrigemGB)
            Write-Host ("Livre destino.: {0:N2} GB" -f $cmp.LivresDestinoGB)
            Write-Host ("Margem........: {0:N2} GB" -f $cmp.MargemGB)
            Write-Host ("Pode copiar?..: {0}" -f $( if ($cmp.PodeCopiar) { "SIM" } else { "NÃO" } )) -ForegroundColor $( if ($cmp.PodeCopiar) { 'Green' } else { 'Red' } )
            if ($cmp.PodeCopiar -and (Confirm-Action -Prompt "Executar cópia unilateral SEGURA agora?")) {
                Start-RobocopyUnilateralSeguro -Origem $origem -Destino $destino
            }
            Pause-Script
        }
        default { Write-Host "Cancelado."; Pause-Script }
    }
}

function Resolve-ShareToDiskInfoV2 {
    <#
      .SYNOPSIS  Resolve \\servidor\share para caminho físico e disco/volume.
      .OUTPUTS   PSCustomObject { Server, Share, PhysicalPath, DriveId, VolumeName, FreeSpace }
    #>
    param([Parameter(Mandatory=$true)][string]$UncPath)

    if ($UncPath -notlike "\\*") { throw "Caminho não é UNC: $UncPath" }

    $parts = $UncPath.TrimEnd('\').Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 2) { throw "UNC inválido: $UncPath" }
    $server = $parts[0]; $shareName = $parts[1]

    # Sessão CIM via DCOM (evita TrustedHosts/WinRM)
    $sess = New-CimSession -ComputerName $server -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop
    try {
        $share = Get-CimInstance -CimSession $sess -ClassName Win32_Share -Filter ("Name='{0}'" -f $shareName) -ErrorAction Stop
        if (-not $share -or [string]::IsNullOrWhiteSpace($share.Path)) {
            throw "Compartilhamento '$shareName' não encontrado em $server."
        }

        $physical = $share.Path # ex: D:\Dados\Softwares
        $root     = [IO.Path]::GetPathRoot($physical)   # ex: D:\

        # 1) tenta Win32_LogicalDisk (discos com letra)
        $driveId = $null; $free = $null; $volName = $null
        if ($root -and $root.Length -ge 2) {
            $driveId = $root.Substring(0,2)             # D:
            $disk = Get-CimInstance -CimSession $sess -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $driveId) -ErrorAction SilentlyContinue
            if ($disk) { $free = [int64]$disk.FreeSpace }
        }

        # 2) fallback para Win32_Volume (montagens sem letra/pontos de montagem)
        if (-not $free -or $free -le 0) {
            $vols = Get-CimInstance -CimSession $sess -ClassName Win32_Volume -ErrorAction Stop
            # Win32_Volume.Name termina com \ (ex: D:\  OU  C:\Mounts\Dados\)
            $vol = $vols | Where-Object { $physical.StartsWith($_.Name, [StringComparison]::OrdinalIgnoreCase) } |
                   Sort-Object { $_.Name.Length } -Descending | Select-Object -First 1
            if ($vol) {
                $free    = [int64]$vol.FreeSpace
                $volName = $vol.Name
                if (-not $driveId -and $vol.DriveLetter) { $driveId = $vol.DriveLetter }
            }
        }

        [pscustomobject]@{
            Server       = $server
            Share        = $shareName
            PhysicalPath = $physical
            DriveId      = $driveId
            VolumeName   = $volName
            FreeSpace    = $free
        }
    }
    finally {
        if ($sess) { Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue }
    }
}

function VerificarEspacoEmDiscoV2 {
    <#
      .SYNOPSIS  Verifica espaço livre para caminho local ou UNC (DCOM).
      .PARAMETER caminho  Caminho local (C:\...) ou UNC (\\server\share\...)
      .PARAMETER MinLivresGB  Limite mínimo em GB (default 1 GB)
      .RETURNS   [bool]
    #>
    param(
        [Parameter(Mandatory=$true)][string]$caminho,
        [double]$MinLivresGB = 1.0
    )

    try {
        $free = $null

        if ($caminho -like "\\*") {
            $info = Resolve-ShareToDiskInfoV2 -UncPath $caminho
            $free = [int64]$info.FreeSpace
        } else {
            $root = [IO.Path]::GetPathRoot($caminho).TrimEnd('\')
            $drv  = Get-PSDrive -Name $root.Trim(':') -ErrorAction Stop
            $free = [int64]$drv.Free
        }

        if (-not $free -or $free -le 0) {
            Write-Warning "Não foi possível determinar o espaço livre para '$caminho'."
            return $false
        }

        $gb = [Math]::Round($free/1GB,2)
        if ($gb -lt $MinLivresGB) {
            Write-Warning ("Espaço insuficiente no destino ({0:N2} GB livres; mínimo {1:N2} GB)." -f $gb, $MinLivresGB)
            return $false
        }

        Write-Host ("Espaço disponível no destino: {0:N2} GB." -f $gb) -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Falha ao verificar espaço para '$caminho'. Detalhe: $($_.Exception.Message)"
        return $false
    }
}

function Get-TamanhoPastaBytesV2 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -Path $Path -PathType Container)) { throw "Pasta não encontrada: $Path" }
    ($items = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue) | Out-Null
    return ($items | Measure-Object -Property Length -Sum).Sum
}

function Comparar-EspacoVsOrigemV2 {
    <#
      .SYNOPSIS  Compara tamanho da origem com espaço livre no destino.
      .RETURNS   PSCustomObject { OrigemGB, LivresDestinoGB, MargemGB, PodeCopiar }
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [double]$MargemSegurancaGB = 2.0
    )

    $tamBytes = Get-TamanhoPastaBytesV2 -Path $Origem
    # reutiliza VerificarEspacoEmDiscoV2 para obter livres
    $livres = $null
    if ($Destino -like "\\*") {
        $info   = Resolve-ShareToDiskInfoV2 -UncPath $Destino
        $livres = [int64]$info.FreeSpace
    } else {
        $root = [IO.Path]::GetPathRoot($Destino).TrimEnd('\')
        $drv  = Get-PSDrive -Name $root.Trim(':')
        $livres = [int64]$drv.Free
    }

    $origemGB = [Math]::Round($tamBytes/1GB,2)
    $livresGB = [Math]::Round($livres/1GB,2)
    $margemGB = [Math]::Round($livresGB - $origemGB,2)
    $ok = ($margemGB -ge $MargemSegurancaGB)

    [pscustomobject]@{
        OrigemGB        = $origemGB
        LivresDestinoGB = $livresGB
        MargemGB        = $margemGB
        PodeCopiar      = $ok
    }
}

# ───────────────────────── Nucleo PURO (Fase B) ─────────────────────────
# Logica sem UI (sem Write-Host/Read-Host/Pause): parametrizavel e testavel.
# Os presenters Start-Robocopy* abaixo consomem estas funcoes.

function Get-RobocopyArgs {
    <#
      .SYNOPSIS  Monta a lista de argumentos do robocopy para os modos seguros V2.
      .DESCRIPTION  Funcao PURA (sem I/O): mesma ordem/flags que os presenters usavam
        inline, agora num so lugar. 'Unilateral' usa /E /XO + (/COPYALL|/COPY:DAT);
        'Espelho' usa /MIR /COPYALL (destrutivo). -Simular adiciona /L (dry-run).
      .OUTPUTS  string[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [Parameter(Mandatory=$true)][ValidateSet('Unilateral','Espelho')][string]$Modo,
        [Parameter(Mandatory=$true)][string]$LogPath,
        [switch]$Simular,
        [switch]$PreservarTudo,
        [ValidateRange(1,128)][int]$Threads = 16,   # /MT: cópia é limitada por latência por-arquivo; 16 > 8 em árvores grandes
        [switch]$Detalhado,                         # /V: lista CADA arquivo no log (auditoria). Padrão = só resumo
        [switch]$IoNaoBufferizado,                  # /J: I/O sem buffer, acelera arquivos grandes (imagens/VMs/ISOs)
        [string[]]$ExcluirDirs,                     # /XD: nomes/caminhos de pasta a pular (ex.: caches de perfil)
        [string[]]$ExcluirArquivos                  # /XF: nomes/wildcards de arquivo a pular (ex.: hives travados)
    )
    # SEM /TEE: com /MT a saída por-thread se intercala no console (e no transcript de sessão) ->
    # texto picotado. Gravamos só no /LOG (robocopy serializa cada registro -> arquivo limpo) e o
    # presenter resume no fim. /BYTES: contadores em bytes crus -> resumo final parseável (sem "2.204 g").
    # /NP: sem o medidor de progresso por-arquivo (escrita char-a-char custa I/O e nada agrega em lote).
    $comum = @('/R:1','/W:1','/XJ',"/MT:$Threads",'/NP','/BYTES',"/LOG+:$LogPath",'/DCOPY:DAT')
    # Padrão = só resumo (/NDL /NFL): log enxuto, nada de flood de arquivos idênticos. -Detalhado volta /V.
    if ($Detalhado) { $comum += '/V' } else { $comum += @('/NDL','/NFL') }
    if ($IoNaoBufferizado) { $comum += '/J' }
    # /XD e /XF aceitam multiplos alvos apos a flag: pular lixo travado (cache/hive) economiza
    # retries (ERRO 32) e nao copia o que nunca seria dado util de backup.
    if ($ExcluirDirs)     { $comum += '/XD'; $comum += $ExcluirDirs }
    if ($ExcluirArquivos) { $comum += '/XF'; $comum += $ExcluirArquivos }
    if ($Modo -eq 'Espelho') {
        $rcArgs = @($Origem, $Destino, '/MIR', '/COPYALL') + $comum
    } else {
        $copyFlag = if ($PreservarTudo) { '/COPYALL' } else { '/COPY:DAT' }
        $rcArgs = @($Origem, $Destino, '/E', '/XO') + $comum + @($copyFlag)
    }
    if ($Simular) { $rcArgs += '/L' }
    return ,$rcArgs
}

function Get-RobocopyStatus {
    <#
      .SYNOPSIS  Classifica o exit code do robocopy (era triplicado nos presenters).
      .DESCRIPTION  Funcao PURA. Robocopy: >=8 erro grave; 1-7 houve copias; 0 nada a fazer.
      .OUTPUTS  PSCustomObject { ExitCode, Severidade('Erro'|'Sucesso'|'SemMudancas'), Mensagem }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][int]$ExitCode)
    if ($ExitCode -ge 8) {
        $sev = 'Erro';        $msg = "Robocopy terminou com erros (código $ExitCode)."
    } elseif ($ExitCode -ge 1) {
        $sev = 'Sucesso';     $msg = "Concluído com sucesso (houve cópias/atualizações)."
    } else {
        $sev = 'SemMudancas'; $msg = "Nada a copiar/alterar (já idêntico)."
    }
    [pscustomobject]@{ ExitCode = $ExitCode; Severidade = $sev; Mensagem = $msg }
}

function Resolve-RobocopyTuning {
    <#
      .SYNOPSIS  Escolhe Threads/Rapido/IoNaoBufferizado a partir do PERFIL da arvore. Funcao PURA.
      .DESCRIPTION  Heuristica: arquivos grandes => /J + poucas threads (banda/IO domina);
        muitos arquivos pequenos => -Rapido + muitas threads (latencia por-arquivo domina);
        caso medio => mais threads que o default. Sem I/O: recebe os numeros ja medidos.
      .OUTPUTS  PSCustomObject { Threads, Rapido, IoNaoBufferizado, Motivo }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory=$true)][int]$FileCount,
        [Parameter(Mandatory=$true)][int64]$TotalBytes,
        [Parameter(Mandatory=$true)][int64]$MaxFileBytes
    )
    $avg = if ($FileCount -gt 0) { $TotalBytes / $FileCount } else { 0 }
    $rapido = $false; $io = $false; $threads = 16
    if ($MaxFileBytes -ge 4GB -or ($FileCount -gt 0 -and $FileCount -le 100 -and $avg -ge 256MB)) {
        $io = $true; $threads = 8
        $motivo = "arquivos grandes (maior {0:N1} GB) -> /J + /MT:8" -f ($MaxFileBytes/1GB)
    } elseif ($FileCount -ge 5000) {
        $rapido = $true; $threads = 32
        $motivo = "muitos arquivos ($FileCount) -> log resumido + /MT:32"
    } elseif ($FileCount -ge 1000) {
        $threads = 24
        $motivo = "$FileCount arquivos -> /MT:24"
    } else {
        $motivo = "$FileCount arquivo(s) -> padrao /MT:16"
    }
    [pscustomobject]@{ Threads = $threads; Rapido = $rapido; IoNaoBufferizado = $io; Motivo = $motivo }
}

function ConvertTo-TamanhoLegivel {
    <#  .SYNOPSIS  Bytes -> string legivel (GB/MB/KB/B). Funcao PURA.  #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory=$true)][int64]$Bytes)
    if     ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N1} MB' -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { '{0:N1} KB' -f ($Bytes / 1KB) }
    else                    { "$Bytes B" }
}

function Format-RobocopyResumo {
    <#
      .SYNOPSIS  Reescreve o resumo final do robocopy numa tabela PT alinhada. Funcao PURA.
      .DESCRIPTION  A tabela nativa do robocopy colide colunas em PT-BR ("IgnoradaIncompatibilidade")
        e formata bytes com espaco ("2.204 g") -> ilegivel. Aqui parseamos as 3 linhas de contadores
        (Dirs/Arquivos/Bytes) por POSICAO (locale-independente): sao as 3 primeiras linhas com 6
        inteiros — exige /BYTES (bytes crus, sem sufixo). Bytes viram GB/MB legiveis. Devolve $null
        se nao der pra parsear (ex.: sem /BYTES), e o caller mantem a saida nativa.
      .OUTPUTS  [string] (multilinha) ou $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # NAO Mandatory: em [string[]], Mandatory rejeita $null/''/@('') (linhas em branco do log
        # lido antes do flush do robocopy) com "empty string". Toleramos e devolvemos $null.
        [AllowNull()][AllowEmptyString()][AllowEmptyCollection()][string[]]$Linhas = @()
    )
    if (-not $Linhas -or $Linhas.Count -eq 0) { return $null }

    $rows = @(); $idxBytes = -1
    for ($i = 0; $i -lt $Linhas.Count; $i++) {
        if ($Linhas[$i] -match ':\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$') {
            $rows += ,@([int64]$Matches[1],[int64]$Matches[2],[int64]$Matches[3],[int64]$Matches[4],[int64]$Matches[5],[int64]$Matches[6])
            $idxBytes = $i
            if ($rows.Count -ge 3) { break }
        }
    }
    if ($rows.Count -lt 3) { return $null }   # sem /BYTES ou saida inesperada
    $dirs = $rows[0]; $arqs = $rows[1]; $byts = $rows[2]

    # Tempo total: primeiro hh:mm:ss APOS a linha de bytes (evita pegar o horario do cabecalho).
    $tempo = $null
    for ($i = $idxBytes + 1; $i -lt $Linhas.Count; $i++) {
        if ($Linhas[$i] -match '(\d+:\d{2}:\d{2})') { $tempo = $Matches[1]; break }
    }

    $fmt = '{0,-12}{1,11}{2,11}{3,11}{4,11}{5,11}'
    $sb  = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('──────────────────────────── Resumo ────────────────────────────')
    [void]$sb.AppendLine(($fmt -f '', 'Total', 'Copiado', 'Ignorado', 'FALHA', 'Extra'))
    [void]$sb.AppendLine(($fmt -f 'Diretórios:', $dirs[0], $dirs[1], $dirs[2], $dirs[4], $dirs[5]))
    [void]$sb.AppendLine(($fmt -f 'Arquivos:',   $arqs[0], $arqs[1], $arqs[2], $arqs[4], $arqs[5]))
    [void]$sb.AppendLine(($fmt -f 'Bytes:',
        (ConvertTo-TamanhoLegivel $byts[0]), (ConvertTo-TamanhoLegivel $byts[1]),
        (ConvertTo-TamanhoLegivel $byts[2]), (ConvertTo-TamanhoLegivel $byts[4]),
        (ConvertTo-TamanhoLegivel $byts[5])))
    if ($tempo) { [void]$sb.AppendLine("Tempo total: $tempo") }
    [void]$sb.Append('─────────────────────────────────────────────────────────────────')
    return $sb.ToString()
}

function Get-ExclusoesPerfil {
    <#
      .SYNOPSIS  Lista de lixo travado/inutil de um perfil Windows p/ robocopy /XD e /XF. Funcao PURA.
      .DESCRIPTION  Hives vivos (NTUSER.DAT, UsrClass.dat e seus *.LOG1/2), caches de browser/SO e
        temporarios: sempre em uso (ERRO 32) e sem valor de backup. Nomes "soltos" em /XD casam a
        pasta em qualquer nivel; wildcards em /XF casam por nome de arquivo.
      .OUTPUTS  PSCustomObject { Dirs[], Arquivos[] }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    [pscustomobject]@{
        Dirs = @(
            'Temp','Cache','Caches','Code Cache','GPUCache','CacheStorage','DXCache','GLCache',
            'ShaderCache','INetCache','WebCache','$RECYCLE.BIN','System Volume Information'
        )
        Arquivos = @(
            'NTUSER.DAT*','ntuser.dat*','UsrClass.dat*','*.LOG1','*.LOG2',
            '*.tmp','*.etl','index.dat','WebCacheV01.dat'
        )
    }
}

function Test-OrigemEhPerfil {
    <#
      .SYNOPSIS  True se a origem e a raiz de perfis (C:\Users), um perfil, ou contem um hive NTUSER.DAT.
      .DESCRIPTION  Guia o auto-exclude de lixo: so liga as exclusoes de perfil quando a origem
        realmente e um perfil de usuario; copias comuns ficam intactas.
      .OUTPUTS  [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory=$true)][string]$Path)
    $sep = [IO.Path]::DirectorySeparatorChar
    $p   = $Path.TrimEnd('\','/')
    $usersRoot = (Join-Path $env:SystemDrive 'Users').TrimEnd('\')
    if ($p -ieq $usersRoot) { return $true }                                               # C:\Users
    if ($p.StartsWith($usersRoot + $sep, [StringComparison]::OrdinalIgnoreCase)) { return $true }  # C:\Users\<...>
    if (Test-Path -LiteralPath (Join-Path $Path 'NTUSER.DAT')) { return $true }            # qualquer pasta com hive
    return $false
}

function Measure-ArvoreRapido {
    <#
      .SYNOPSIS  Mede a arvore (contagem/bytes/maior arquivo) com teto p/ nao custar caro.
      .DESCRIPTION  Uma passada com Get-ChildItem; para em -LimiteArquivos (basta p/ classificar
        "muitos arquivos"). Robocopy reenumera de qualquer forma; isto so guia o auto-tune.
      .OUTPUTS  PSCustomObject { FileCount, TotalBytes, MaxFileBytes, Truncado }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$LimiteArquivos = 20000
    )
    $count = 0; $total = [int64]0; $max = [int64]0; $trunc = $false
    foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $count++; $len = [int64]$f.Length; $total += $len
        if ($len -gt $max) { $max = $len }
        if ($count -ge $LimiteArquivos) { $trunc = $true; break }
    }
    [pscustomobject]@{ FileCount = $count; TotalBytes = $total; MaxFileBytes = $max; Truncado = $trunc }
}

function Test-ParOrigemDestino {
    <#
      .SYNOPSIS  Valida o par origem/destino antes de qualquer robocopy (guard central).
      .DESCRIPTION  Origem deve existir e ser pasta; origem != destino (compara caminhos
        NORMALIZADOS, ignorando case e barra final). Escreve o erro e devolve $false quando
        invalido. Chamado pelas presenters V2 -> cobre tanto o menu interativo quanto o
        modo automatizado (-Acao Sincronizar) num so lugar.
      .OUTPUTS  [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino
    )
    if (-not (Test-Path -LiteralPath $Origem -PathType Container)) {
        Write-Error "Origem inexistente ou não é uma pasta: $Origem"
        return $false
    }
    # Destino pode ainda nao existir (robocopy cria); so normaliza o que da pra resolver.
    $oReal = (Convert-Path -LiteralPath $Origem).TrimEnd('\')
    $dReal = if (Test-Path -LiteralPath $Destino) { (Convert-Path -LiteralPath $Destino).TrimEnd('\') } else { $Destino.TrimEnd('\') }
    if ($oReal -ieq $dReal) {
        Write-Error "Origem e destino não podem ser o mesmo caminho: $oReal"
        return $false
    }
    # Aninhamento: destino DENTRO da origem (ou vice-versa) faz /MIR e /E copiarem em
    # recursao/apagarem o que nao deviam. Compara com separador para evitar falso-positivo
    # de prefixo (ex.: C:\Dados vs C:\Dados2).
    $sep = [IO.Path]::DirectorySeparatorChar
    if ($dReal.StartsWith($oReal + $sep, [StringComparison]::OrdinalIgnoreCase) -or
        $oReal.StartsWith($dReal + $sep, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Error "Origem e destino não podem estar aninhados (um dentro do outro): '$oReal' x '$dReal'."
        return $false
    }
    return $true
}

function Show-RobocopyResultado {
    <#
      .SYNOPSIS  Lê o log do robocopy e imprime resumo limpo + digest de erros + status final.
      .DESCRIPTION  Como nao usamos /TEE (evita o texto picotado do /MT), a saida vive no /LOG.
        Aqui: 1) resumo PT alinhado (Format-RobocopyResumo); 2) contagem de ERRO N (arquivos em
        uso/sem permissao) sem floodar a tela; 3) mensagem de severidade (Get-RobocopyStatus).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][int]$ExitCode
    )
    $linhas = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
    $resumo = Format-RobocopyResumo -Linhas $linhas
    if ($resumo) { Write-Host ''; Write-Host $resumo -ForegroundColor Cyan }

    $erros = @($linhas | Where-Object { $_ -match '(?:ERRO|ERROR)\s+\d+\s' })
    if ($erros.Count) {
        Write-Host ("{0} arquivo(s) não copiado(s) (em uso / sem permissão). Detalhes no log." -f $erros.Count) -ForegroundColor Yellow
    }

    $st = Get-RobocopyStatus -ExitCode $ExitCode
    if ($st.Severidade -eq 'Erro') { Write-Error ("{0} Veja o log: {1}" -f $st.Mensagem, $LogPath) }
    else                           { Write-Host  ("{0} Log: {1}" -f $st.Mensagem, $LogPath) -ForegroundColor Green }
}

function Start-RobocopyUnilateralSeguro {
    <#
      .SYNOPSIS  Cópia unilateral (Origem -> Destino) com flags seguras e /dry-run opcional.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [switch]$Simular,          # adiciona /L (lista sem copiar)
        [switch]$IgnorarEspaco,    # pula checagem de espaço
        [switch]$PreservarTudo,    # /COPYALL (ACL/owner/auditing) em vez de /COPY:DAT
        [double]$MinLivresGB = 1.0,
        [ValidateRange(1,128)][int]$Threads = 16,  # /MT
        [switch]$Detalhado,                         # /V: lista por-arquivo no log (default = só resumo)
        [switch]$IoNaoBufferizado,                  # /J (arquivos grandes)
        [switch]$SemAutoTune,                       # desliga o auto-tune (usa os valores acima/default)
        [switch]$SemExclusaoPerfil                  # nao auto-exclui lixo travado mesmo se a origem for perfil
    )

    $copiaDesc = if ($PreservarTudo) { 'COMPLETA (/COPYALL: ACL/owner)' } else { 'segura (/COPY:DAT)' }
    Write-Host "------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Origem : $Origem"
    Write-Host "Destino: $Destino"
    Write-Host "Modo   : Unilateral $copiaDesc$(if($Simular){' - SIMULAÇÃO (/L)'}else{''})"
    Write-Host "------------------------------------------------" -ForegroundColor Cyan

    if (-not (Test-ParOrigemDestino -Origem $Origem -Destino $Destino)) { return }

    # Auto-tune: se o caller NAO fixou nenhum parametro de velocidade, escolhe sozinho a
    # partir do perfil da origem (muitos arquivos pequenos vs poucos grandes). -SemAutoTune opta fora.
    $tunavel = -not ($PSBoundParameters.ContainsKey('Threads') -or $PSBoundParameters.ContainsKey('IoNaoBufferizado'))
    if (-not $SemAutoTune -and $tunavel) {
        $m = Measure-ArvoreRapido -Path $Origem
        $t = Resolve-RobocopyTuning -FileCount $m.FileCount -TotalBytes $m.TotalBytes -MaxFileBytes $m.MaxFileBytes
        $Threads = $t.Threads; $IoNaoBufferizado = [switch]$t.IoNaoBufferizado
        Write-Host ("Auto-tune: {0}{1}" -f $t.Motivo, $(if($m.Truncado){" (amostra >= $($m.FileCount))"}else{''})) -ForegroundColor DarkCyan
    }

    # Origem = perfil de usuario? Auto-exclui hives travados + caches (ERRO 32 / lixo). -SemExclusaoPerfil opta fora.
    $exDirs = @(); $exFiles = @()
    if (-not $SemExclusaoPerfil -and (Test-OrigemEhPerfil -Path $Origem)) {
        $ex = Get-ExclusoesPerfil; $exDirs = $ex.Dirs; $exFiles = $ex.Arquivos
        Write-Host ("Origem é perfil de usuário: excluindo lixo travado ({0} pastas / {1} padrões de arquivo)." -f $exDirs.Count, $exFiles.Count) -ForegroundColor DarkCyan
    }

    if (-not $IgnorarEspaco) {
        $ok = VerificarEspacoEmDiscoV2 -caminho $Destino -MinLivresGB $MinLivresGB
        if (-not $ok) {
            Write-Warning "Espaço não validado/suficiente. Use -IgnorarEspaco para prosseguir mesmo assim."
            return
        }
    }

    $log = Join-Path -Path (Get-SyncMasterDataDir -SubPasta 'Logs') -ChildPath ("robocopy_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))

    # Argumentos via nucleo puro (Get-RobocopyArgs): /COPYALL preserva ACL/owner/auditing
    # (precisa admin); /COPY:DAT evita Owner/SACL.
    $rcArgs = Get-RobocopyArgs -Origem $Origem -Destino $Destino -Modo 'Unilateral' -LogPath $log -Simular:$Simular -PreservarTudo:$PreservarTudo -Threads $Threads -Detalhado:$Detalhado -IoNaoBufferizado:$IoNaoBufferizado -ExcluirDirs $exDirs -ExcluirArquivos $exFiles

    Write-Host "Copiando... (saída por-arquivo vai pro log; resumo ao final)" -ForegroundColor Yellow
    & robocopy @rcArgs
    $rc = $LASTEXITCODE
    Registrar-Log ("Robocopy unilateral {0} {1} -> {2} (rc={3}){4}" -f $copiaDesc, $Origem, $Destino, $rc, $(if($Simular){' [SIMULACAO]'}else{''}))
    Show-RobocopyResultado -LogPath $log -ExitCode $rc
}

function Start-RobocopyEspelho {
    <#
      .SYNOPSIS  Espelha Origem -> Destino com /MIR (DESTRUTIVO: apaga no destino o que nao existe na origem).
      .DESCRIPTION  Checa espaco (V2), loga e suporta /L (dry-run). Preserva ACL/owner via /COPYALL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [switch]$Simular,
        [switch]$IgnorarEspaco,
        [double]$MinLivresGB = 1.0,
        [ValidateRange(1,128)][int]$Threads = 16,  # /MT
        [switch]$Detalhado,                         # /V: lista por-arquivo no log (default = só resumo)
        [switch]$IoNaoBufferizado,                  # /J (arquivos grandes)
        [switch]$SemAutoTune,                       # desliga o auto-tune (usa os valores acima/default)
        [switch]$SemExclusaoPerfil                  # nao auto-exclui lixo travado mesmo se a origem for perfil
    )

    Write-Host "------------------------------------------------" -ForegroundColor Red
    Write-Host "Origem : $Origem"
    Write-Host "Destino: $Destino"
    Write-Host "Modo   : ESPELHO /MIR$(if($Simular){' - SIMULAÇÃO (/L)'}else{''})" -ForegroundColor Red
    Write-Host "AVISO: tudo no destino que NAO existe na origem sera APAGADO." -ForegroundColor Red
    Write-Host "------------------------------------------------" -ForegroundColor Red

    if (-not (Test-ParOrigemDestino -Origem $Origem -Destino $Destino)) { return }

    # Auto-tune (igual a unilateral): so quando o caller nao fixou parametros de velocidade.
    $tunavel = -not ($PSBoundParameters.ContainsKey('Threads') -or $PSBoundParameters.ContainsKey('IoNaoBufferizado'))
    if (-not $SemAutoTune -and $tunavel) {
        $m = Measure-ArvoreRapido -Path $Origem
        $t = Resolve-RobocopyTuning -FileCount $m.FileCount -TotalBytes $m.TotalBytes -MaxFileBytes $m.MaxFileBytes
        $Threads = $t.Threads; $IoNaoBufferizado = [switch]$t.IoNaoBufferizado
        Write-Host ("Auto-tune: {0}{1}" -f $t.Motivo, $(if($m.Truncado){" (amostra >= $($m.FileCount))"}else{''})) -ForegroundColor DarkCyan
    }

    if (-not $IgnorarEspaco) {
        $ok = VerificarEspacoEmDiscoV2 -caminho $Destino -MinLivresGB $MinLivresGB
        if (-not $ok) {
            Write-Warning "Espaço não validado/suficiente. Use -IgnorarEspaco para prosseguir mesmo assim."
            return
        }
    }

    # Origem = perfil? Auto-exclui lixo travado. Em /MIR o /XD tambem PROTEGE: pasta excluida nao e apagada no destino.
    $exDirs = @(); $exFiles = @()
    if (-not $SemExclusaoPerfil -and (Test-OrigemEhPerfil -Path $Origem)) {
        $ex = Get-ExclusoesPerfil; $exDirs = $ex.Dirs; $exFiles = $ex.Arquivos
        Write-Host ("Origem é perfil de usuário: excluindo lixo travado ({0} pastas / {1} padrões de arquivo)." -f $exDirs.Count, $exFiles.Count) -ForegroundColor DarkCyan
    }

    $log = Join-Path -Path (Get-SyncMasterDataDir -SubPasta 'Logs') -ChildPath ("robocopy_espelho_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
    $rcArgs = Get-RobocopyArgs -Origem $Origem -Destino $Destino -Modo 'Espelho' -LogPath $log -Simular:$Simular -Threads $Threads -Detalhado:$Detalhado -IoNaoBufferizado:$IoNaoBufferizado -ExcluirDirs $exDirs -ExcluirArquivos $exFiles

    Write-Host "Espelhando... (saída por-arquivo vai pro log; resumo ao final)" -ForegroundColor Yellow
    & robocopy @rcArgs
    $rc = $LASTEXITCODE
    Registrar-Log ("Robocopy ESPELHO /MIR {0} -> {1} (rc={2}){3}" -f $Origem, $Destino, $rc, $(if($Simular){' [SIMULACAO]'}else{''}))
    Show-RobocopyResultado -LogPath $log -ExitCode $rc
}

function Iniciar-SincronizacaoV2 {
    # Retrocompat: os menus "1" e "1.1" foram unificados em Iniciar-Sincronizacao.
    Iniciar-Sincronizacao
}

function Agendar-TarefaSincronizacao {
    Write-Host "--- AGENDAMENTO DE TAREFA DE SINCRONIZAÇÃO ---" -ForegroundColor Cyan
    $hora = Read-Host "Digite a hora para agendar a sincronização diária (formato HH:mm, ex: 22:00)"
    if ($hora -notmatch "^\d{2}:\d{2}$") { Write-Warning "Formato de hora inválido."; Pause-Script; return }
    
    $origemObj = Selecionar-DiretorioDaLista -Titulo "Selecione a ORIGEM da sincronização agendada"
    if (-not $origemObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    $destinoObj = Selecionar-DiretorioDaLista -Titulo "Selecione o DESTINO da sincronização agendada"
    if (-not $destinoObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    # Caminho do SCRIPT DE ENTRADA (nao deste .psm1): o launcher exporta SYNCMASTER_ENTRY.
    # $MyInvocation.MyCommand.Definition aqui dentro do modulo apontava para Sync.psm1 (bug):
    # a Tarefa Agendada chamava o modulo em vez do Sync_Master.ps1.
    $entryScript = if ($env:SYNCMASTER_ENTRY -and (Test-Path $env:SYNCMASTER_ENTRY)) {
        $env:SYNCMASTER_ENTRY
    } else {
        Join-Path (Split-Path $PSScriptRoot -Parent) 'Sync_Master.ps1'
    }
    if (-not (Test-Path $entryScript)) {
        Write-Warning "Script de entrada nao localizado ($entryScript). Abra o Sync Master pelo Sync_Master.ps1 e tente de novo."
        Pause-Script; return
    }

    $nomeTarefa = "SincronizacaoEngOrtiz_" + (Get-Date -Format "yyyyMMdd")
    $trigger = New-ScheduledTaskTrigger -Daily -At $hora
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    # Prefere o PS7, exceto o alias por usuario da Microsoft Store: a tarefa roda como SYSTEM
    # e nao consegue executar um App Execution Alias de %LOCALAPPDATA% de outro usuario.
    # Nesse caso, powershell.exe serve: o launcher trata PS5 no modo automatizado sem prompt.
    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    $pwshPath = if ($pwshCmd) { if ($pwshCmd.Source) { $pwshCmd.Source } else { $pwshCmd.Path } }
    $storeAliasDir = if ($env:LOCALAPPDATA) { [IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'WindowsApps') }
    $isStoreAlias = $pwshPath -and $storeAliasDir -and $pwshPath.StartsWith($storeAliasDir, [StringComparison]::OrdinalIgnoreCase)
    $exe = if ($pwshPath -and -not $isStoreAlias) { $pwshPath } else { "powershell.exe" }
    $action = New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$entryScript`" -Acao Sincronizar -Origem `"$($origemObj.Caminho)`" -Destino `"$($destinoObj.Caminho)`""
    
    try {
        Register-ScheduledTask -TaskName $nomeTarefa -Trigger $trigger -Action $action -Principal $principal -Description "Sincronização automática configurada pela Ferramenta de Engenharia." -Force
        Write-Host "Tarefa '$nomeTarefa' agendada com sucesso para executar diariamente às $hora!" -ForegroundColor Green
        Registrar-Log "Tarefa agendada: $nomeTarefa"
    } catch {
        Write-Warning "Falha ao agendar a tarefa. Erro: $($_.Exception.Message)"
    }
    Pause-Script
}

Export-ModuleMember -Function Salvar-Diretorios, Menu-GerenciamentoDiretorios, Selecionar-DiretorioDaLista, ObterCaminhoPasta, Iniciar-Sincronizacao, Resolve-ShareToDiskInfoV2, VerificarEspacoEmDiscoV2, Get-TamanhoPastaBytesV2, Comparar-EspacoVsOrigemV2, Get-RobocopyArgs, Get-RobocopyStatus, Resolve-RobocopyTuning, Measure-ArvoreRapido, ConvertTo-TamanhoLegivel, Format-RobocopyResumo, Show-RobocopyResultado, Get-ExclusoesPerfil, Test-OrigemEhPerfil, Test-ParOrigemDestino, Start-RobocopyUnilateralSeguro, Start-RobocopyEspelho, Iniciar-SincronizacaoV2, Agendar-TarefaSincronizacao
