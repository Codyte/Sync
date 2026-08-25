<#
    Ativacao.psm1 — ativacao do Windows.
    Extraido do monolito legado (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

function Menu-Ativacao {
    do {
        Clear-Host; Write-Host "--- GERENCIAMENTO DE ATIVAÇÃO (FERRAMENTAS OFICIAIS) ---" -ForegroundColor Cyan
        Write-Host "1 - Mostrar Status Detalhado da Ativação"
        Write-Host "2 - Instalar uma Chave de Produto (Product Key)"
        Write-Host "3 - Tentar Ativação Online"
        Write-Host "Q - Voltar ao Menu Principal"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            "1" { Mostrar-StatusAtivacao }
            "2" { Instalar-ChaveProduto }
            "3" { Ativar-Windows }
            "4" { Ati }
            "Q" { return }
            default { Write-Warning "Opção inválida." }
        }
    } while ($true)
}

function Mostrar-StatusAtivacao {
    Write-Host "Exibindo informações detalhadas de licenciamento..." -ForegroundColor Yellow
    Start-Process -FilePath "cscript.exe" -ArgumentList "//nologo C:\Windows\System32\slmgr.vbs /dlv" -Wait
    Pause-Script
}

function Instalar-ChaveProduto {
    $productKey = Read-Host -Prompt "Por favor, insira a chave de produto legítima (Product Key)"
    if ([string]::IsNullOrWhiteSpace($productKey)) { Write-Warning "Nenhuma chave inserida. Operação cancelada." }
    else {
        Write-Host "Instalando a chave de produto..." -ForegroundColor Yellow
        Start-Process -FilePath "cscript.exe" -ArgumentList "//nologo C:\Windows\System32\slmgr.vbs /ipk $productKey" -Wait
    }
    Pause-Script
}

function Ati {
    # Endurecimento (supply-chain): baixa->SHA256->confirma, com pin opcional, e
    # executa via scriptblock (em vez de Invoke-Expression). Mesmo padrao do Executor/WinUtil.
    param(
        [string]$Url = 'https://get.activated.win',
        [string]$ExpectedSha256 = $env:MAS_EXPECTED_SHA256
    )
    Write-Host "ATENCAO: isto baixa e EXECUTA um script remoto de $Url (Microsoft Activation Scripts)." -ForegroundColor Yellow
    Write-Host "Executar codigo remoto sem inspecionar e um risco de seguranca." -ForegroundColor Yellow

    try {
        $script = Invoke-RestMethod -Uri $Url -ErrorAction Stop
    } catch {
        Write-Warning "Falha ao baixar o ativador. Verifique a conexão/antivírus: $($_.Exception.Message)"
        Pause-Script
        return
    }
    if ([string]::IsNullOrWhiteSpace($script)) { Write-Warning "Conteudo baixado vazio. Abortando."; Pause-Script; return }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($script)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    try   { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }   # SHA256::Create() e' IDisposable
    Write-Host ("Tamanho: {0:N0} bytes | SHA256: {1}" -f $bytes.Length, $hash) -ForegroundColor Cyan

    if ($ExpectedSha256) {
        if ($hash -ne $ExpectedSha256.Trim().ToLowerInvariant()) {
            Write-Warning "SHA256 NAO corresponde ao esperado ($ExpectedSha256). ABORTANDO por seguranca."
            Pause-Script
            return
        }
        Write-Host "SHA256 confere com o esperado." -ForegroundColor Green
    }

    if (-not (Confirm-Action -Prompt "Executar o ativador com o SHA256 acima ?")) {
        Write-Host "Cancelado." -ForegroundColor DarkGray
        Pause-Script
        return
    }
    try {
        Registrar-Log "Ativar-Crack: executando MAS de $Url (sha256=$hash)"
        & ([scriptblock]::Create($script))
    } catch {
        Write-Warning "Falha ao executar o ativador: $($_.Exception.Message)"
    }
    Pause-Script
}


function Ativar-Windows {
    Write-Host "Tentando ativar o Windows online..." -ForegroundColor Yellow
    Start-Process -FilePath "cscript.exe" -ArgumentList "//nologo C:\Windows\System32\slmgr.vbs /ato" -Wait
    Pause-Script
}

Export-ModuleMember -Function Menu-Ativacao, Mostrar-StatusAtivacao, Instalar-ChaveProduto, Ativar-Windows
