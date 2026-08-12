# Pester 5 — Fase C: menu principal data-driven (modules\Menu.psm1).
# Rodar:  Invoke-Pester -Path .\tests
# Get-MenuPrincipal e dado puro -> da' para validar integridade da tabela sem UI.

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'SyncMaster.psd1') -Force -DisableNameChecking
    $script:Entradas = Get-MenuPrincipal
    $tokens = $null; $errors = $null
    $launcherAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root 'Sync_Master.ps1'), [ref]$tokens, [ref]$errors
    )
    $script:LauncherAst = $launcherAst
    $script:MenuAvancadoAst = $launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Menu-Avancado'
    }, $true) | Select-Object -First 1
    # Acoes definidas no launcher .ps1 (nao em modulo): nao resolvem no teste; sao toleradas.
    $script:LauncherLocais = @('Menu-Otimizacao','Criar-App')
}

Describe 'Get-MenuPrincipal (tabela)' {
    It 'tem entradas' { $script:Entradas.Count | Should -BeGreaterThan 0 }

    It 'Ids sao unicos' {
        $ids = $script:Entradas.Id
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'todo item tem Id, Texto e Comando nao-vazios' {
        foreach ($e in $script:Entradas) {
            $e.Id      | Should -Not -BeNullOrEmpty
            $e.Texto   | Should -Not -BeNullOrEmpty
            $e.Comando | Should -Not -BeNullOrEmpty
        }
    }

    It 'tem exatamente uma sentinela de saida (__SAIR__)' {
        ($script:Entradas | Where-Object Comando -eq '__SAIR__').Count | Should -Be 1
    }

    It 'cobre os Ids esperados' {
        $ids = $script:Entradas.Id
        foreach ($req in '1','5','10','15','APP','Q') { $ids | Should -Contain $req }
    }

    It 'todo Comando real (nao-sentinela, nao-local) resolve para uma funcao' {
        foreach ($e in $script:Entradas) {
            if ($e.Comando -eq '__SAIR__' -or $e.Comando -in $script:LauncherLocais) { continue }
            Get-Command $e.Comando -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because "Comando '$($e.Comando)' (Id $($e.Id)) deve existir"
        }
    }
}

Describe 'Show-MenuPrincipal (render)' {
    It 'nao lanca ao renderizar a tabela' {
        { Show-MenuPrincipal -Entradas $script:Entradas 6>$null } | Should -Not -Throw
    }
}

Describe 'Menu-Avancado (seguranca)' {
    It 'nao expoe execucao livre de BCDEDIT' {
        $script:MenuAvancadoAst | Should -Not -BeNullOrEmpty
        $script:MenuAvancadoAst.Extent.Text | Should -Not -Match '(?i)\bbcdedit\b'
    }
}

Describe 'Menu principal (codigo remoto)' {
    It 'nao anuncia nem define o executor remoto do WinUtil' {
        $script:Entradas.Comando | Should -Not -Contain 'Executor'
        $executor = $script:LauncherAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Executor'
        }, $true)
        $executor.Count | Should -Be 0
    }
}
