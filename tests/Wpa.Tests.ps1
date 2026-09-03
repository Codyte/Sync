# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
# ======================= END NAV INDEX =======================

# Pester 5 — comportamento do arsenal WPA (modules\Ativacao.psm1).
# Rodar:  Invoke-Pester -Path .\tests
#
# Os testes de Menu.Tests.ps1 sao estaticos: garantem o contorno do modulo lendo
# o fonte. Aqui a logica roda de verdade, com mocks, porque o custo de errar e
# alto: parar o sppsvc e nao religar, ou queimar 40 minutos de DISM a toa.

# O estado compartilhado destes testes e global de proposito: um mock e um bloco
# InModuleScope rodam em session states diferentes, entao $script: nao e o mesmo
# nos dois lados. WaitForStatus falso precisa da assinatura, nao dos argumentos.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
param()

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Ativacao.psm1') -Force -DisableNameChecking
}

Describe 'Get-WpaSupportedWindows' {
    It 'aceita Windows 11 desktop x64' {
        InModuleScope Ativacao {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    Caption = 'Windows 11 Pro'; Version = '10.0.22631'
                    BuildNumber = '22631'; ProductType = 1
                }
            }
            (Get-WpaSupportedWindows).Caption | Should -Be 'Windows 11 Pro'
        }
    }

    It 'aceita Windows 10 desktop x64' {
        InModuleScope Ativacao {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    Caption = 'Windows 10 Pro'; Version = '10.0.19045'
                    BuildNumber = '19045'; ProductType = 1
                }
            }
            (Get-WpaSupportedWindows).Caption | Should -Be 'Windows 10 Pro'
        }
    }

    It 'recusa Windows Server' {
        InModuleScope Ativacao {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    Caption = 'Windows Server 2022'; Version = '10.0.20348'
                    BuildNumber = '20348'; ProductType = 3
                }
            }
            { Get-WpaSupportedWindows } | Should -Throw '*desktop x64*'
        }
    }
}

Describe 'Get-WpaActivationState' {
    It 'trata grace period como nao licenciado, mas distinto de sem licenca' {
        InModuleScope Ativacao {
            Mock Get-CimInstance { [PSCustomObject]@{ LicenseStatus = 5 } }
            $state = Get-WpaActivationState
            $state.Licensed | Should -BeFalse
            $state.StatusCode | Should -Be 5
            $state.StatusText | Should -Be 'Notificacao'
        }
    }

    It 'e licenciado quando qualquer produto Windows esta em LicenseStatus 1' {
        InModuleScope Ativacao {
            Mock Get-CimInstance {
                @([PSCustomObject]@{ LicenseStatus = 0 }, [PSCustomObject]@{ LicenseStatus = 1 })
            }
            (Get-WpaActivationState).Licensed | Should -BeTrue
        }
    }

    It 'sem produto algum reporta sem licenca em vez de estourar' {
        InModuleScope Ativacao {
            Mock Get-CimInstance { @() }
            $state = Get-WpaActivationState
            $state.StatusCode | Should -Be 0
            $state.Licensed | Should -BeFalse
        }
    }
}

Describe 'Invoke-WpaGuidedRepair' {
    BeforeEach {
        # Estado do teste vive em escopo global: mock e InModuleScope rodam em
        # session states diferentes, e $script: nao e o mesmo nos dois.
        $global:WpaTeste = @{ Licenciado = $false; Operacoes = @() }
        Mock -ModuleName Ativacao Get-WpaSupportedWindows { [PSCustomObject]@{ Caption = 'Windows 10 Pro' } }
        Mock -ModuleName Ativacao Require-Admin { }
        Mock -ModuleName Ativacao Confirm-Action { $true }
        Mock -ModuleName Ativacao Registrar-Log { }
        Mock -ModuleName Ativacao Write-Host { }
        Mock -ModuleName Ativacao Write-Warning { }
        Mock -ModuleName Ativacao Repair-WpaServices { }
        Mock -ModuleName Ativacao Invoke-WpaActivationRepair { }
        Mock -ModuleName Ativacao Invoke-WpaLicenseFileRepair { }
        Mock -ModuleName Ativacao Clear-WpaKmsConfig { }
        Mock -ModuleName Ativacao Reset-WpaTokens { }
        Mock -ModuleName Ativacao Repair-WpaSystemFiles { }
        Mock -ModuleName Ativacao Invoke-Slmgr { }
        Mock -ModuleName Ativacao Get-WpaActivationState {
            [PSCustomObject]@{
                Licensed   = [bool]$global:WpaTeste.Licenciado
                StatusCode = if ($global:WpaTeste.Licenciado) { 1 } else { 0 }
                StatusText = if ($global:WpaTeste.Licenciado) { 'Licenciado' } else { 'Sem licenca' }
            }
        }
    }

    # O ponto da escada: nao gastar 40 minutos de DISM depois que o /ato resolveu.
    It 'para no degrau que licencia e nao executa os seguintes' {
        Mock -ModuleName Ativacao Invoke-WpaActivationRepair { $global:WpaTeste.Licenciado = $true }

        InModuleScope Ativacao { Invoke-WpaGuidedRepair }

        Should -Invoke -ModuleName Ativacao Repair-WpaServices -Times 1 -Exactly
        Should -Invoke -ModuleName Ativacao Invoke-WpaActivationRepair -Times 1 -Exactly
        Should -Invoke -ModuleName Ativacao Invoke-WpaLicenseFileRepair -Times 0 -Exactly
        Should -Invoke -ModuleName Ativacao Clear-WpaKmsConfig -Times 0 -Exactly
        Should -Invoke -ModuleName Ativacao Reset-WpaTokens -Times 0 -Exactly
        Should -Invoke -ModuleName Ativacao Repair-WpaSystemFiles -Times 0 -Exactly
    }

    It 'percorre a escada inteira quando nada licencia' {
        InModuleScope Ativacao { Invoke-WpaGuidedRepair }

        Should -Invoke -ModuleName Ativacao Repair-WpaServices -Times 1 -Exactly
        Should -Invoke -ModuleName Ativacao Reset-WpaTokens -Times 1 -Exactly
        Should -Invoke -ModuleName Ativacao Repair-WpaSystemFiles -Times 1 -Exactly
    }

    It 'nao toca em nada quando o Windows ja esta licenciado' {
        $global:WpaTeste.Licenciado = $true

        InModuleScope Ativacao { Invoke-WpaGuidedRepair }

        Should -Invoke -ModuleName Ativacao Confirm-Action -Times 0 -Exactly
        Should -Invoke -ModuleName Ativacao Repair-WpaServices -Times 0 -Exactly
    }

    # Um degrau que estoura nao pode derrubar a escada: o proximo ainda tem chance.
    It 'segue para o proximo degrau quando um deles falha' {
        Mock -ModuleName Ativacao Repair-WpaServices { throw 'servico travado' }

        InModuleScope Ativacao { Invoke-WpaGuidedRepair }

        Should -Invoke -ModuleName Ativacao Invoke-WpaActivationRepair -Times 1 -Exactly
        Should -Invoke -ModuleName Ativacao Repair-WpaSystemFiles -Times 1 -Exactly
    }

    It 'pula o degrau que o usuario recusar' {
        Mock -ModuleName Ativacao Confirm-Action { $false }

        InModuleScope Ativacao { Invoke-WpaGuidedRepair }

        Should -Invoke -ModuleName Ativacao Repair-WpaServices -Times 0 -Exactly
        Should -Invoke -ModuleName Ativacao Repair-WpaSystemFiles -Times 0 -Exactly
    }
}

Describe 'Reset-WpaTokens' {
    BeforeEach {
        $sppsvc = [PSCustomObject]@{
            Status = [System.ServiceProcess.ServiceControllerStatus]::Running
        }
        $sppsvc | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value { param($s, $t) }
        $global:WpaTeste = @{ Operacoes = @(); Sppsvc = $sppsvc }
        Mock -ModuleName Ativacao Get-WpaSupportedWindows { }
        Mock -ModuleName Ativacao Require-Admin { }
        Mock -ModuleName Ativacao Backup-WpaRegistry { 'C:\dados\WPA-teste.reg' }
        Mock -ModuleName Ativacao Get-WindowsDirectory { 'C:\Windows' }
        Mock -ModuleName Ativacao Test-Path { $true }
        Mock -ModuleName Ativacao Get-Service { $global:WpaTeste.Sppsvc }
        Mock -ModuleName Ativacao Stop-Service { }
        Mock -ModuleName Ativacao Start-Service { }
        Mock -ModuleName Ativacao Start-Sleep { }
        Mock -ModuleName Ativacao Registrar-Log { }
        Mock -ModuleName Ativacao Invoke-Slmgr { $global:WpaTeste.Operacoes += $Operation }
    }

    # A falha que deixaria a maquina pior que antes: sppsvc parado e sem volta.
    It 'religa o sppsvc quando o rename do tokens.dat nao passa' {
        Mock -ModuleName Ativacao Rename-Item { throw 'arquivo em uso' }

        InModuleScope Ativacao { { Reset-WpaTokens } | Should -Throw '*continua em uso*' }

        Should -Invoke -ModuleName Ativacao Start-Service -Times 1 -Exactly
        Should -Invoke -ModuleName Ativacao Invoke-Slmgr -Times 0 -Exactly
    }

    It 'renomeia o tokens.dat e reinstala as licencas na ordem certa' {
        Mock -ModuleName Ativacao Rename-Item { }

        $resultado = InModuleScope Ativacao { Reset-WpaTokens }

        Should -Invoke -ModuleName Ativacao Rename-Item -Times 1 -Exactly
        $global:WpaTeste.Operacoes | Should -Be @('/rilc', '/ato')
        $resultado.RegistryBackup | Should -Be 'C:\dados\WPA-teste.reg'
        $resultado.TokensBackup | Should -Match 'tokens-\d{8}-\d{6}\.bak$'
    }

    It 'exporta a chave WPA antes de parar o servico' {
        Mock -ModuleName Ativacao Rename-Item { }
        Mock -ModuleName Ativacao Backup-WpaRegistry { throw 'sem permissao para exportar' }

        InModuleScope Ativacao { { Reset-WpaTokens } | Should -Throw '*sem permissao*' }

        Should -Invoke -ModuleName Ativacao Stop-Service -Times 0 -Exactly
    }
}

Describe 'Invoke-Slmgr (ativacao por telefone)' {
    It 'recusa ID de confirmacao fora dos 48 digitos' {
        InModuleScope Ativacao {
            { Invoke-Slmgr -Operation '/atp' -ConfirmationId '12345' } | Should -Throw '*48 digitos*'
        }
    }

    # Com o ID valido a validacao passa e o fluxo so para na checagem do binario
    # nativo — que e onde este teste barra a execucao real de uma ativacao.
    It 'aceita o ID de confirmacao com os separadores da central' {
        InModuleScope Ativacao {
            Mock Require-Admin { }
            Mock Get-WindowsDirectory { 'C:\NaoExiste' }
            $id = '123456-123456-123456-123456-123456-123456-123456-123456'
            { Invoke-Slmgr -Operation '/atp' -ConfirmationId $id } | Should -Throw '*Arquivo nativo ausente*'
        }
    }

    It 'recusa ConfirmationId em operacao que nao seja /atp' {
        InModuleScope Ativacao {
            { Invoke-Slmgr -Operation '/ato' -ConfirmationId ('1' * 48) } |
                Should -Throw '*so pode ser usado com /atp*'
        }
    }
}

Describe 'Invoke-WpaTriage' {
    BeforeEach {
        # Mesmo motivo do bloco da escada: mock e InModuleScope rodam em session
        # states diferentes, entao o estado do caso vive em escopo global.
        $global:WpaTeste = @{
            HiveMegaBytes = 22
            Inchado       = $false
            Ativador      = $false
            SemElevacao   = $false
            Licenciado    = $true
            Novas         = 0
        }
        Mock -ModuleName Ativacao Get-WpaSupportedWindows { [PSCustomObject]@{ Caption = 'Windows 10 Pro' } }
        Mock -ModuleName Ativacao Registrar-Log { }
        Mock -ModuleName Ativacao Write-Host { }
        Mock -ModuleName Ativacao Write-Warning { }
        Mock -ModuleName Ativacao Get-WpaHiveSize {
            [PSCustomObject]@{
                Path      = 'C:\Windows\System32\config\SYSTEM'
                Bytes     = [long]$global:WpaTeste.HiveMegaBytes * 1MB
                MegaBytes = $global:WpaTeste.HiveMegaBytes
                Inchado   = [bool]$global:WpaTeste.Inchado
            }
        }
        Mock -ModuleName Ativacao Test-WpaActivatorFootprint {
            [PSCustomObject]@{
                Detected = [bool]$global:WpaTeste.Ativador
                Limitado = [bool]$global:WpaTeste.SemElevacao
                Evidence = @(if ($global:WpaTeste.Ativador) { 'Tarefa agendada com cara de renovador: \AutoKMS' })
            }
        }
        Mock -ModuleName Ativacao Get-WpaDiagnostic {
            [PSCustomObject]@{ Windows = 'Windows 10 Pro'; WpaSubkeyCount = 1200; SppErrors7Days = 0 }
        }
        Mock -ModuleName Ativacao Get-WpaActivationState {
            [PSCustomObject]@{
                Licensed   = [bool]$global:WpaTeste.Licenciado
                StatusCode = if ($global:WpaTeste.Licenciado) { 1 } else { 5 }
                StatusText = if ($global:WpaTeste.Licenciado) { 'Licenciado' } else { 'Notificacao' }
            }
        }
        Mock -ModuleName Ativacao Measure-WpaGrowth {
            [PSCustomObject]@{ Seconds = 5; NewSubkeys = [int]$global:WpaTeste.Novas }
        }
        Mock -ModuleName Ativacao Find-WpaPsExec64 { $null }
        Mock -ModuleName Ativacao Invoke-WpaSystemProbe { }
    }

    # A bifurcacao inteira: com ativador vivo, reparar e tratar sintoma. Ele vence
    # ate quando todo o resto parece saudavel.
    It 'ativador presente vence os outros sinais' {
        $global:WpaTeste.Ativador = $true
        $global:WpaTeste.Novas = 3
        $global:WpaTeste.Licenciado = $false

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'ATIVADOR PRESENTE'
        $resultado.Proximo | Should -Match 'Remova o ativador'
    }

    It 'crescimento no intervalo vem antes do estado da licenca' {
        $global:WpaTeste.Novas = 7
        $global:WpaTeste.Licenciado = $false

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'CRESCENDO AGORA'
    }

    It 'licenca inativa sem crescimento manda para o reparo guiado' {
        $global:WpaTeste.Licenciado = $false

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'LICENCA NAO ATIVA (Notificacao)'
        $resultado.Proximo | Should -Match 'opcao 16'
    }

    # Licenciado, parado e inchado: o Sync Master nao encolhe a arvore, entao o
    # veredito precisa dizer isso em vez de prometer faxina.
    It 'arvore inchada, parada e licenciada e cicatriz antiga' {
        $global:WpaTeste.Inchado = $true
        $global:WpaTeste.HiveMegaBytes = 480

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'CICATRIZ ANTIGA'
        $resultado.Proximo | Should -Match 'nao encolhe'
    }

    It 'maquina saudavel nao inventa problema' {
        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'NORMAL'
        $resultado.Avisos.Count | Should -Be 0
    }

    # Um coletor que estoura nao pode derrubar a triagem: os outros ainda rodam e
    # a falha vira orientacao.
    It 'coletor que falha vira aviso e nao derruba a triagem' {
        Mock -ModuleName Ativacao Get-WpaHiveSize { throw 'Acesso negado' }

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'NORMAL'
        $resultado.Avisos -join ' ' | Should -Match 'administrador'
        Should -Invoke -ModuleName Ativacao Measure-WpaGrowth -Times 1 -Exactly
    }

    It 'sem dado nenhum conclui inconclusivo em vez de chutar' {
        Mock -ModuleName Ativacao Get-WpaHiveSize { throw 'Acesso negado' }
        Mock -ModuleName Ativacao Get-WpaDiagnostic { throw 'WPA ilegivel' }
        Mock -ModuleName Ativacao Get-WpaActivationState { throw 'CIM fora do ar' }
        Mock -ModuleName Ativacao Measure-WpaGrowth { throw 'WPA ilegivel' }

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'INCONCLUSIVO'
        $resultado.Avisos.Count | Should -Be 4
    }

    # 'Nao detectei ativador' sem elevacao nao e a mesma frase que com elevacao:
    # a chave OEM do firmware, que sustenta o indicio mais forte, volta vazia.
    It 'marca que o rastreio de ativador rodou cego sem elevacao' {
        $global:WpaTeste.SemElevacao = $true

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Veredito | Should -Be 'NORMAL'
        $resultado.Avisos -join ' ' | Should -Match 'sem elevacao'
    }

    It 'nao repete o aviso de elevacao quando o ativador foi detectado' {
        $global:WpaTeste.SemElevacao = $true
        $global:WpaTeste.Ativador = $true

        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        $resultado.Avisos -join ' ' | Should -Not -Match 'sem elevacao'
    }

    It 'nao roda a sonda como SYSTEM sem o switch' {
        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 }

        Should -Invoke -ModuleName Ativacao Invoke-WpaSystemProbe -Times 0 -Exactly
        $resultado.Sonda | Should -BeNullOrEmpty
    }

    # PsExec ausente e o caso comum, e a licenca Sysinternals impede embutir o
    # binario: entao a triagem precisa orientar, nunca falhar calada.
    It 'orienta quando a sonda foi pedida e o PsExec nao existe' {
        $resultado = InModuleScope Ativacao { Invoke-WpaTriage -Seconds 5 -IncluirSondaSystem }

        $resultado.Veredito | Should -Be 'NORMAL'
        $resultado.Avisos -join ' ' | Should -Match 'opcao 3'
    }
}
AfterAll {
    Remove-Variable -Name WpaTeste -Scope Global -ErrorAction SilentlyContinue
}
