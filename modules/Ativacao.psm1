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

function Ativar-Windows {
    Write-Host "Tentando ativar o Windows online..." -ForegroundColor Yellow
    Start-Process -FilePath "cscript.exe" -ArgumentList "//nologo C:\Windows\System32\slmgr.vbs /ato" -Wait
    Pause-Script
}

Export-ModuleMember -Function Menu-Ativacao, Mostrar-StatusAtivacao, Instalar-ChaveProduto, Ativar-Windows
