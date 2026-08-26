<#
    Ferramentas.psm1 — instalacao de utilitarios de gerenciamento via winget.

    Mesmo padrao data-driven do Menu.psm1: Get-CatalogoFerramentas devolve uma TABELA
    (dado puro, testavel) e Show/Menu so renderizam + despacham.
    Acrescentar um utilitario = uma linha na tabela; nenhum 'switch' a editar.

    A instalacao REUSA Invoke-WingetInstall (PowerShellUpdate.psm1), que ja trata os tres
    tropecos do winget: ausencia do executavel, --accept-*-agreements (1o uso prompta e
    travaria o menu) e $LASTEXITCODE (exe nativo com exit != 0 NAO lanca excecao).
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1')             -DisableNameChecking  # Registrar-Log, Pause-Script
Import-Module (Join-Path $PSScriptRoot 'PowerShellUpdate.psm1') -DisableNameChecking  # Invoke-WingetInstall
Import-Module (Join-Path $PSScriptRoot 'Otimizacao.psm1')       -DisableNameChecking  # Parse-Selection
# SEM -Force nos tres: -Force aninhado remove o modulo global do launcher (ver nota em PowerShellUpdate.psm1).

function Get-CatalogoFerramentas {
    <#
      .SYNOPSIS  Catalogo de utilitarios de gerenciamento/diagnostico (dado puro, sem UI).
      .DESCRIPTION
        Curado, nao exaustivo: cada entrada faz algo que o Windows nao faz sozinho.
        Deliberadamente FORA: "otimizadores" tipo Advanced SystemCare / Glary / PC Manager —
        envelopam o que o Windows ja faz e o "boost" de RAM e placebo (forcar EmptyWorkingSet
        joga paginas pro disco e o app re-carrega em seguida).
      .OUTPUTS  PSCustomObject[]: Id, Nome, PacoteId, Descricao.
      .NOTES    Todo PacoteId conferido contra 'winget show --id <id> --exact' em 2026-08-26.
    #>
    [CmdletBinding()]
    param()
    @(
        [PSCustomObject]@{ Id=1; Nome='WizTree';            PacoteId='AntibodySoftware.WizTree';        Descricao='Analisador de disco; le a MFT do NTFS (varre TB em segundos)' }
        [PSCustomObject]@{ Id=2; Nome='Sysinternals Suite'; PacoteId='Microsoft.Sysinternals.Suite';    Descricao='Autoruns, Process Explorer, RAMMap, VMMap' }
        [PSCustomObject]@{ Id=3; Nome='UniGetUI';           PacoteId='Devolutions.UniGetUI';            Descricao='Front-end de winget/Store/Choco/Scoop/pip/npm num lugar so' }
        [PSCustomObject]@{ Id=4; Nome='HWiNFO';             PacoteId='REALiX.HWiNFO';                   Descricao='Sensores reais: temperatura, tensao, clock' }
        [PSCustomObject]@{ Id=5; Nome='Everything';         PacoteId='voidtools.Everything';            Descricao='Busca instantanea por nome de arquivo (indice da MFT)' }
        [PSCustomObject]@{ Id=6; Nome='CrystalDiskInfo';    PacoteId='CrystalDewWorld.CrystalDiskInfo'; Descricao='Saude S.M.A.R.T. de HD/SSD' }
        [PSCustomObject]@{ Id=7; Nome='BleachBit';          PacoteId='BleachBit.BleachBit';             Descricao='Limpeza alem do Storage Sense; open source, sem bundleware' }
        [PSCustomObject]@{ Id=8; Nome='PowerToys';          PacoteId='Microsoft.PowerToys';             Descricao='FancyZones, PowerRename, Run, Awake' }
    )
}

function Show-CatalogoFerramentas {
    <#
      .SYNOPSIS  Renderiza o catalogo. So apresentacao.
      .PARAMETER Catalogo  Saida de Get-CatalogoFerramentas (default: a propria).
    #>
    [CmdletBinding()]
    param([PSCustomObject[]]$Catalogo = (Get-CatalogoFerramentas))

    try { Clear-Host } catch { Write-Verbose $_.Exception.Message }  # host sem console (ex.: Pester)
    Write-Host "======================================================" -ForegroundColor DarkGray
    Write-Host "  INSTALAR FERRAMENTAS DE GERENCIAMENTO (winget)" -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor DarkGray
    foreach ($f in $Catalogo) {
        Write-Host ("{0,3} - {1}" -f $f.Id, $f.Nome) -ForegroundColor Gray -NoNewline
        Write-Host ("  [{0}]" -f $f.PacoteId) -ForegroundColor DarkGray
        Write-Host ("      {0}" -f $f.Descricao) -ForegroundColor DarkCyan
    }
    Write-Host "======================================================" -ForegroundColor DarkGray
    Write-Host "  T - Todos os itens acima      Q - Voltar" -ForegroundColor Yellow
}

function Install-Ferramenta {
    <#
      .SYNOPSIS  Instala/atualiza UM item do catalogo e registra o resultado no log.
      .DESCRIPTION
        Envelope fino sobre Invoke-WingetInstall: o valor aqui e o Registrar-Log com o nome
        legivel + PacoteId, para o historico dizer O QUE foi instalado e nao so um Id opaco.
      .OUTPUTS  [bool] $true so em sucesso real (o proprio criterio do Invoke-WingetInstall).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory=$true)][PSCustomObject]$Ferramenta)

    Write-Host ("`n--- {0} [{1}] ---" -f $Ferramenta.Nome, $Ferramenta.PacoteId) -ForegroundColor Cyan
    if (Invoke-WingetInstall -PackageId $Ferramenta.PacoteId) {
        Registrar-Log ("Ferramenta instalada/atualizada: {0} [{1}]" -f $Ferramenta.Nome, $Ferramenta.PacoteId)
        return $true
    }
    Registrar-Log ("FALHA ao instalar ferramenta: {0} [{1}]" -f $Ferramenta.Nome, $Ferramenta.PacoteId)
    return $false
}

function Menu-InstalarFerramentas {
    <#
      .SYNOPSIS  Instala/atualiza utilitarios de gerenciamento via winget.
      .DESCRIPTION
        Selecao multipla no mesmo formato do Menu-Startups ("1 3 5-7"), reusando
        Parse-Selection. 'T' = todos, 'Q' = volta. Falha de um item NAO aborta os demais:
        o resumo do fim diz quantos entraram e quais falharam.
      .PARAMETER Catalogo  Saida de Get-CatalogoFerramentas (injetavel para teste).
    #>
    [CmdletBinding()]
    param([PSCustomObject[]]$Catalogo = (Get-CatalogoFerramentas))

    do {
        Show-CatalogoFerramentas -Catalogo $Catalogo
        $opcao = Read-Host "`nNumeros (ex.: 1 3 5-7), T = todos, Q = voltar"
        if ([string]::IsNullOrWhiteSpace($opcao)) { continue }
        $sel = $opcao.Trim().ToUpper()
        if ($sel -eq 'Q') { return }

        # if/else e nao 'switch' de proposito: 'continue' dentro de switch continua o SWITCH,
        # nao o do/while — a selecao invalida cairia direto na instalacao com $alvos vazio.
        if ($sel -eq 'T') {
            $alvos = @($Catalogo)
        } else {
            $indices = Parse-Selection -Selection $sel -Max $Catalogo.Count
            if (-not $indices) {
                Write-Host "Selecao invalida." -ForegroundColor Red
                Start-Sleep -Seconds 2
                continue
            }
            $alvos = @($Catalogo | Where-Object { $_.Id -in $indices })
        }

        $ok = 0
        $falhou = @()
        foreach ($f in $alvos) {
            if (Install-Ferramenta -Ferramenta $f) { $ok++ } else { $falhou += $f.Nome }
        }
        Write-Host ("`n{0} de {1} concluido(s)." -f $ok, $alvos.Count) -ForegroundColor Green
        if ($falhou.Count -gt 0) { Write-Warning ("Falharam: {0}" -f ($falhou -join ', ')) }
        Pause-Script
    } while ($true)
}

Export-ModuleMember -Function Get-CatalogoFerramentas, Show-CatalogoFerramentas, Install-Ferramenta, Menu-InstalarFerramentas
