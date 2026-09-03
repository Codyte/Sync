# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
# ======================= END NAV INDEX =======================

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
    $script:LauncherText = Get-Content (Join-Path $root 'Sync_Master.ps1') -Raw
    $script:AtivacaoText = Get-Content (Join-Path $root 'modules\Ativacao.psm1') -Raw
    $script:OtimizacaoText = Get-Content (Join-Path $root 'modules\Otimizacao.psm1') -Raw
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

Describe 'Menu de ativacao' {
    It 'mantem a opcao 4 oculta no menu' {
        # Escopo: o corpo de Menu-Ativacao. O menu WPA tem uma opcao 4 propria e visivel,
        # entao a assercao de "oculta" nao pode varrer o modulo inteiro.
        $corpo = [regex]::Match($script:AtivacaoText, '(?ms)^function Menu-Ativacao \{.*?^\}').Value
        $corpo | Should -Not -BeNullOrEmpty
        $corpo | Should -Match '(?m)^\s*[''"]4[''"]\s*\{\s*Ati\s*\}\s*$'
        $corpo | Should -Not -Match 'Write-Host\s+[''"]4\s*[-.]'
    }

    # A opcao 4 (Microsoft Activation Scripts) e' deliberada e FICA — decisao do dono do repo,
    # 2026-08-26; antes daqui o teste exigia um placeholder no lugar dela. O que este teste
    # ainda trava e' o contorno: o ativador nao roda sem as guardas.
    It 'nao executa o ativador remoto sem SHA256 e sem confirmacao explicita' {
        $script:AtivacaoText | Should -Match '\bSHA256\b'
        $script:AtivacaoText | Should -Match '\bConfirm-Action\b'
        $script:AtivacaoText | Should -Match 'scriptblock\]::Create'   # nunca Invoke-Expression
    }
}

Describe 'Menu WPA (2 -> 2 -> 6)' {
    It 'o submenu de reparo do sistema oferece e despacha a opcao 6' {
        $corpo = [regex]::Match($script:LauncherText, '(?ms)^function Menu-ReparoSistema \{.*?^\}').Value
        $corpo | Should -Not -BeNullOrEmpty
        $corpo | Should -Match '(?m)^\s*Write-Host\s+"6\.'
        $corpo | Should -Match "(?m)^\s*'6'\s*\{\s*Menu-GerenciamentoWpa\s*\}"
    }

    It 'o manifesto exporta o menu WPA' {
        (Import-PowerShellDataFile -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'SyncMaster.psd1')).FunctionsToExport |
            Should -Contain 'Menu-GerenciamentoWpa'
    }

    # O ponto inteiro do modulo: diagnosticar sem destruir. Apagar HKLM\SYSTEM\WPA nao tem
    # contrato oficial de reconstrucao; se alguem reintroduzir isso, este teste reprova.
    It 'nunca remove a chave HKLM\SYSTEM\WPA' {
        $script:AtivacaoText | Should -Not -Match '(?i)Remove-Item[^
]*WPA'
        $script:AtivacaoText | Should -Not -Match '(?i)reg(\.exe)?[^
]*delete'
    }

    # A triagem e a porta de entrada do menu: se o despacho sumir, o usuario cai
    # de novo em escolher a esmo entre 17 opcoes.
    It 'o menu WPA oferece e despacha a triagem na opcao 0' {
        $corpo = [regex]::Match($script:AtivacaoText, '(?ms)^function Menu-GerenciamentoWpa \{.*?^\}').Value
        $corpo | Should -Match "(?m)^\s*Write-Host '0\s+- Triagem completa"
        $bloco = [regex]::Match($corpo, "(?ms)'0'\s*\{.*?\r?\n                \}").Value
        $bloco | Should -Match 'Invoke-WpaTriage'
    }

    It 'so executa o PsExec depois de validar produto e assinatura Microsoft' {
        $script:AtivacaoText | Should -Match 'Get-AuthenticodeSignature'
        $script:AtivacaoText | Should -Match 'Sysinternals PsExec'
        $corpo = [regex]::Match($script:AtivacaoText, '(?ms)^function Invoke-WpaSystemProbe \{.*?^\}').Value
        $corpo | Should -Match 'Test-WpaPsExec64File'
    }
}

Describe 'Otimizacao (seguranca e utilidade)' {
    It 'nao mantem tweaks perigosos ou sem beneficio geral' {
        $codigo = $script:LauncherText + $script:OtimizacaoText
        $codigo | Should -Not -Match '(?i)DisablePagingExecutive|LargeSystemCache|AllowTelemetry'
        $codigo | Should -Not -Match '(?i)PROCTHROTTLEMIN|IDLEDISABLE|behavior\s+set\s+memoryusage'
        $codigo | Should -Not -Match '(?i)Disable-ScheduledTask|Stop-Service\s+WSearch'
        $codigo | Should -Not -Match '(?i)(Add|Set)-MpPreference[^\r\n]*Exclusion'
    }

    It 'nao expoe mais os menus avancados removidos' {
        $funcoes = $script:LauncherAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in @('Menu-Avancado','Menu-OtimizacaoAvancada','Gerenciar-EstadosOciososProcessador')
        }, $true)
        $funcoes.Count | Should -Be 0
    }

    It 'mede antes/depois e expoe somente acoes documentadas no menu de desempenho' {
        $script:LauncherText | Should -Match '\bGet-PerformanceSnapshot\b'
        $script:LauncherText | Should -Match '\bCompare-LatestPerformanceSnapshots\b'
        $script:LauncherText | Should -Match '\bInvoke-DefenderQuickScan\b|\bMenu-DefenderPerformance\b'
        $script:LauncherText | Should -Match 'ms-settings:windowsupdate'
        $script:LauncherText | Should -Match 'ms-settings:storagepolicies'
        $script:LauncherText | Should -Match 'ms-settings:privacy-backgroundapps'
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

Describe 'Arsenal de correcao WPA' {
    # A escada so tem valor se estiver ordenada do menos ao mais invasivo e se
    # parar assim que o Windows licenciar; caso contrario roda DISM a toa.
    It 'o reparo guiado escalona e para no primeiro degrau que licenciar' {
        $corpo = [regex]::Match($script:AtivacaoText, '(?ms)^function Invoke-WpaGuidedRepair \{.*?^\}').Value
        $corpo | Should -Not -BeNullOrEmpty
        $degraus = [regex]::Matches($corpo, "Nome\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        $degraus.Count | Should -BeGreaterThan 3
        $degraus[0] | Should -Match 'servicos'
        $degraus[-1] | Should -Match 'DISM'
        $corpo | Should -Match '\$newState = Get-WpaActivationState'
        $corpo | Should -Match 'if \(\$newState\.Licensed\)'
    }

    # Backup antes de mexer: tokens.dat, /upk e /rearm sao caminhos sem volta facil.
    It 'as correcoes sem volta exportam a chave WPA antes' -ForEach @(
        @{ Funcao = 'Reset-WpaTokens' }
        @{ Funcao = 'Uninstall-WpaProductKey' }
        @{ Funcao = 'Invoke-WpaRearm' }
    ) {
        $corpo = [regex]::Match($script:AtivacaoText, "(?ms)^function $Funcao \{.*?^\}").Value
        $corpo | Should -Not -BeNullOrEmpty
        $corpo | Should -Match 'Backup-WpaRegistry'
    }

    # tokens.dat corrompido e a causa real de boa parte dos casos; renomear
    # preserva a evidencia e permite voltar atras copiando o .bak de volta.
    It 'renomeia o tokens.dat em vez de apagar' {
        $corpo = [regex]::Match($script:AtivacaoText, '(?ms)^function Reset-WpaTokens \{.*?^\}').Value
        $corpo | Should -Match 'Rename-Item'
        $corpo | Should -Not -Match 'Remove-Item'
    }

    It 'toda correcao exige elevacao' -ForEach @(
        @{ Funcao = 'Backup-WpaRegistry' }
        @{ Funcao = 'Repair-WpaServices' }
        @{ Funcao = 'Clear-WpaKmsConfig' }
        @{ Funcao = 'Reset-WpaTokens' }
        @{ Funcao = 'Repair-WpaSystemFiles' }
        @{ Funcao = 'Uninstall-WpaProductKey' }
        @{ Funcao = 'Invoke-WpaRearm' }
        @{ Funcao = 'Invoke-WpaGuidedRepair' }
    ) {
        $corpo = [regex]::Match($script:AtivacaoText, "(?ms)^function $Funcao \{.*?^\}").Value
        $corpo | Should -Not -BeNullOrEmpty
        $corpo | Should -Match '(?m)^\s*Require-Admin\s*$'
    }

    # slmgr /dlv, /dli e /xpr sao leitura pura: pedir elevacao ali afastaria o
    # usuario do diagnostico, que e justamente o passo que deve ser barato.
    It 'os verbos de leitura do slmgr nao pedem elevacao' {
        $corpo = [regex]::Match($script:AtivacaoText, '(?ms)^function Invoke-Slmgr \{.*?^\}').Value
        $corpo | Should -Match "notin @\('/dlv','/dli','/xpr'\)"
    }

    It 'o menu WPA despacha cada correcao do arsenal' -ForEach @(
        @{ Opcao = '8'; Funcao = 'Repair-WpaServices' }
        @{ Opcao = '11'; Funcao = 'Clear-WpaKmsConfig' }
        @{ Opcao = '12'; Funcao = 'Reset-WpaTokens' }
        @{ Opcao = '13'; Funcao = 'Repair-WpaSystemFiles' }
        @{ Opcao = '14'; Funcao = 'Uninstall-WpaProductKey' }
        @{ Opcao = '15'; Funcao = 'Invoke-WpaRearm' }
        @{ Opcao = '16'; Funcao = 'Invoke-WpaGuidedRepair' }
    ) {
        $corpo = [regex]::Match($script:AtivacaoText, '(?ms)^function Menu-GerenciamentoWpa \{.*?^\}').Value
        $bloco = [regex]::Match($corpo, "(?ms)'$Opcao'\s*\{.*?\r?\n                \}").Value
        $bloco | Should -Match $Funcao
    }
}
