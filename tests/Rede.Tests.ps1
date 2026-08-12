# Pester 5 — Fase B: nucleo puro do dominio Rede (modules\Rede.psm1).
# Rodar:  Invoke-Pester -Path .\tests
# Alvo: ConvertFrom-PortSpec (parser de especificacao de portas, sem UI).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Rede.psm1') -Force -DisableNameChecking
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root 'modules\Rede.psm1'), [ref]$tokens, [ref]$errors
    )
    $script:SpeedtestAst = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Instalar-e-Testar-Speedtest'
    }, $true) | Select-Object -First 1
}

Describe 'ConvertFrom-PortSpec' {
    It 'expande intervalos e solta avulsas: "20-22,80,443"' {
        (ConvertFrom-PortSpec -Spec '20-22,80,443') -join ',' | Should -Be '20,21,22,80,443'
    }
    It 'ordena e deduplica' {
        (ConvertFrom-PortSpec -Spec '443,80,80,22') -join ',' | Should -Be '22,80,443'
    }
    It 'aceita espaco e ponto-e-virgula como separadores' {
        (ConvertFrom-PortSpec -Spec '22 80;443') -join ',' | Should -Be '22,80,443'
    }
    It 'ignora intervalo invertido (25-20)' {
        (ConvertFrom-PortSpec -Spec '25-20').Count | Should -Be 0
    }
    It 'descarta portas fora de [1..65535]' {
        (ConvertFrom-PortSpec -Spec '0,70000,443') -join ',' | Should -Be '443'
    }
    It 'ignora tokens nao-numericos' {
        (ConvertFrom-PortSpec -Spec 'abc,ssh,80') -join ',' | Should -Be '80'
    }
    It 'string vazia -> nenhuma porta' {
        (ConvertFrom-PortSpec -Spec '').Count | Should -Be 0
    }
    It 'ignora numeros maiores que Int32 sem lancar' {
        { $script:PortasGrandes = ConvertFrom-PortSpec -Spec '999999999999,1-999999999999,443' } | Should -Not -Throw
        $script:PortasGrandes -join ',' | Should -Be '443'
    }
}

Describe 'Test-TcpPort valida limites antes de abrir socket' {
    It 'rejeita porta fora de [1..65535]' {
        { Test-TcpPort -ComputerName 'localhost' -Port 0 } | Should -Throw
        { Test-TcpPort -ComputerName 'localhost' -Port 65536 } | Should -Throw
    }
}

Describe 'Instalar-e-Testar-Speedtest (cadeia de confianca)' {
    It 'nao instala modulos arbitrarios da PSGallery' {
        $script:SpeedtestAst | Should -Not -BeNullOrEmpty
        $script:SpeedtestAst.Extent.Text | Should -Not -Match '(?i)\bInstall-Module\b'
    }

    It 'exige confirmacao antes de instalar a CLI oficial' {
        $script:SpeedtestAst.Extent.Text | Should -Match '(?is)Confirm-Action.+Ookla\.Speedtest\.CLI'
    }
}
