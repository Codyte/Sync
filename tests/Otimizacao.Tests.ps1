# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
# ======================= END NAV INDEX =======================

# Pester 5 — testes puros e mocks de efeitos externos do Sync Master.
# Rodar:  Invoke-Pester -Path .\tests
# Alvos: Otimizacao.psm1 e helpers de diretorio/log de Core.psm1.

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1')       -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Otimizacao.psm1') -Force -DisableNameChecking
}

Describe 'Parse-Selection' {
    It 'expande numeros soltos e intervalos: "1 3 5-7"' {
        (Parse-Selection -Selection '1 3 5-7' -Max 10) -join ',' | Should -Be '1,3,5,6,7'
    }
    It 'aceita virgula e ponto-e-virgula como separadores' {
        (Parse-Selection -Selection '1;2,3 4' -Max 10) -join ',' | Should -Be '1,2,3,4'
    }
    It 'deduplica e ordena' {
        (Parse-Selection -Selection '5 1 5 3 1' -Max 10) -join ',' | Should -Be '1,3,5'
    }
    It 'descarta fora do intervalo [1..Max]' {
        (Parse-Selection -Selection '0 5 11' -Max 10) -join ',' | Should -Be '5'
    }
    It 'ignora intervalo invertido (7-5)' {
        (Parse-Selection -Selection '7-5' -Max 10).Count | Should -Be 0
    }
    It 'ignora tokens nao-numericos' {
        (Parse-Selection -Selection 'abc x-y' -Max 10).Count | Should -Be 0
    }
    It 'combina intervalo + solto: "5-7,10"' {
        (Parse-Selection -Selection '5-7,10' -Max 12) -join ',' | Should -Be '5,6,7,10'
    }
}

Describe 'Clean-Temp limita a remocao a diretorios temporarios seguros' {
    BeforeEach {
        Mock Require-Admin {} -ModuleName Otimizacao
        Mock 'Dism.exe' { $global:LASTEXITCODE = 0 } -ModuleName Otimizacao
        Mock Registrar-Log {} -ModuleName Otimizacao
        Mock Write-Host {} -ModuleName Otimizacao
        Mock Write-Warning {} -ModuleName Otimizacao
        Mock Remove-Item {} -ModuleName Otimizacao
    }

    It 'nao remove nada quando TEMP e WINDIR estao ausentes' {
        $oldTemp = $env:TEMP; $oldWindir = $env:WINDIR
        try {
            $env:TEMP = $null; $env:WINDIR = $null
            Clean-Temp
            Should -Invoke Remove-Item -ModuleName Otimizacao -Times 0
        } finally {
            $env:TEMP = $oldTemp; $env:WINDIR = $oldWindir
        }
    }

    It 'nao remove nada quando TEMP aponta para a raiz do volume' {
        $oldTemp = $env:TEMP; $oldWindir = $env:WINDIR
        try {
            $env:TEMP = 'C:\'; $env:WINDIR = $null
            Clean-Temp
            Should -Invoke Remove-Item -ModuleName Otimizacao -Times 0
        } finally {
            $env:TEMP = $oldTemp; $env:WINDIR = $oldWindir
        }
    }

    It 'enumera e remove somente filhos literais de um TEMP valido' {
        $oldTemp = $env:TEMP; $oldWindir = $env:WINDIR
        try {
            $env:TEMP = 'C:\Temp'; $env:WINDIR = $null
            Mock Test-Path { $true } -ModuleName Otimizacao
            Mock Get-ChildItem { [pscustomobject]@{ FullName = 'C:\Temp\arquivo[1].tmp' } } -ModuleName Otimizacao

            Clean-Temp

            Should -Invoke Remove-Item -ModuleName Otimizacao -Times 1 -ParameterFilter {
                $LiteralPath -eq 'C:\Temp\arquivo[1].tmp'
            }
        } finally {
            $env:TEMP = $oldTemp; $env:WINDIR = $oldWindir
        }
    }

    It 'registra falha real quando o DISM retorna codigo nao zero' {
        $oldTemp = $env:TEMP; $oldWindir = $env:WINDIR
        try {
            $env:TEMP = $null; $env:WINDIR = $null
            Mock 'Dism.exe' { $global:LASTEXITCODE = 5 } -ModuleName Otimizacao

            Clean-Temp

            Should -Invoke Write-Warning -ModuleName Otimizacao -ParameterFilter { $Message -match 'código 5' }
            Should -Invoke Registrar-Log -ModuleName Otimizacao -Times 1 -ParameterFilter { $msg -match 'DISM=Falha\(5\)' }
        } finally {
            $env:TEMP = $oldTemp; $env:WINDIR = $oldWindir
        }
    }
}

Describe 'Otimizacao nativa de armazenamento' {
    BeforeEach {
        Mock Require-Admin {} -ModuleName Otimizacao
        Mock Get-Volume {
            @(
                [pscustomobject]@{ DriveType = 'Fixed'; DriveLetter = 'C' },
                [pscustomobject]@{ DriveType = 'Removable'; DriveLetter = 'E' }
            )
        } -ModuleName Otimizacao
        Mock Optimize-Volume {} -ModuleName Otimizacao
        Mock Registrar-Log {} -ModuleName Otimizacao
        Mock Write-Host {} -ModuleName Otimizacao
        Mock Write-Warning {} -ModuleName Otimizacao
    }

    It 'deixa o Windows escolher TRIM ou desfragmentacao conforme o volume' {
        Invoke-StorageOptimization -Mode Optimize | Should -BeTrue

        Should -Invoke Optimize-Volume -ModuleName Otimizacao -Times 1 -ParameterFilter {
            $DriveLetter -eq 'C' -and -not $Analyze -and -not $ReTrim -and -not $Defrag -and $ErrorAction -eq 'Stop'
        }
    }

    It 'analisa sem modificar quando solicitado' {
        Invoke-StorageOptimization -Mode Analyze | Should -BeTrue

        Should -Invoke Optimize-Volume -ModuleName Otimizacao -Times 1 -ParameterFilter {
            $DriveLetter -eq 'C' -and $Analyze -and $ErrorAction -eq 'Stop'
        }
    }

    It 'nao anuncia sucesso total quando um volume falha' {
        Mock Optimize-Volume { throw 'falha de volume' } -ModuleName Otimizacao

        Invoke-StorageOptimization -Mode Optimize | Should -BeFalse
        Should -Invoke Write-Warning -ModuleName Otimizacao -ParameterFilter { $Message -match '1 volume' }
    }
}

Describe 'Planos de energia conservadores e verificaveis' {
    BeforeEach {
        Mock powercfg { $global:LASTEXITCODE = 0 } -ModuleName Otimizacao
        Mock Registrar-Log {} -ModuleName Otimizacao
        Mock Write-Host {} -ModuleName Otimizacao
        Mock Write-Warning {} -ModuleName Otimizacao
    }

    It 'aplica Equilibrado como plano recomendado' {
        Set-PowerPlan -Plan Balanced | Should -BeTrue

        Should -Invoke powercfg -ModuleName Otimizacao -Times 1 -ParameterFilter {
            $args -contains 'SCHEME_BALANCED'
        }
        Should -Invoke Registrar-Log -ModuleName Otimizacao -Times 1
    }

    It 'nao registra sucesso quando powercfg falha' {
        Mock powercfg { $global:LASTEXITCODE = 9 } -ModuleName Otimizacao

        Set-PowerPlan -Plan HighPerformance | Should -BeFalse

        Should -Invoke Registrar-Log -ModuleName Otimizacao -Times 0
        Should -Invoke Write-Warning -ModuleName Otimizacao -ParameterFilter { $Message -match 'código 9' }
    }
}

Describe 'Medicao de desempenho antes e depois' {
    It 'coleta somente metricas observaveis do Windows' {
        $oldDrive = $env:SystemDrive
        try {
            $env:SystemDrive = 'C:'
            Mock Get-CimInstance {
                switch ($ClassName) {
                    'Win32_PerfFormattedData_PerfOS_Processor' { [pscustomobject]@{ PercentProcessorTime = 25 } }
                    'Win32_OperatingSystem' { [pscustomobject]@{ TotalVisibleMemorySize = 1000; FreePhysicalMemory = 250; LastBootUpTime = (Get-Date).AddHours(-10) } }
                    'Win32_LogicalDisk' { [pscustomobject]@{ Size = 100GB; FreeSpace = 40GB } }
                    'Win32_ComputerSystem' { [pscustomobject]@{ AutomaticManagedPagefile = $true } }
                    'Win32_QuickFixEngineering' { [pscustomobject]@{ HotFixID = 'KB123'; InstalledOn = [datetime]'2026-08-01' } }
                }
            } -ModuleName Otimizacao
            Mock Get-Startups { @([pscustomobject]@{ Enabled = $true }, [pscustomobject]@{ Enabled = $false }) } -ModuleName Otimizacao
            Mock Get-Process { @([pscustomobject]@{ ProcessName = 'app'; Id = 10; WorkingSet64 = 100MB }) } -ModuleName Otimizacao
            Mock Get-ActivePowerPlan { 'Equilibrado' } -ModuleName Otimizacao
            Mock Get-DefenderStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $true; SignatureAgeDays = 1 } } -ModuleName Otimizacao

            $snapshot = Get-PerformanceSnapshot -CpuSampleCount 1

            $snapshot.SchemaVersion | Should -Be 1
            $snapshot.CpuPercent | Should -Be 25
            $snapshot.MemoryUsedPercent | Should -Be 75
            $snapshot.SystemDriveFreeGB | Should -Be 40
            $snapshot.StartupEnabledCount | Should -Be 1
            $snapshot.AutomaticManagedPageFile | Should -BeTrue
            $snapshot.LastHotFixId | Should -Be 'KB123'
            $snapshot.TopMemoryProcesses[0].Name | Should -Be 'app'
        } finally { $env:SystemDrive = $oldDrive }
    }

    It 'calcula deltas sem inventar uma avaliacao subjetiva' {
        $before = [pscustomobject]@{
            CapturedAt = '2026-08-12T10:00:00-03:00'
            CpuPercent = 70
            MemoryUsedPercent = 80
            SystemDriveFreeGB = 20
            StartupEnabledCount = 12
        }
        $after = [pscustomobject]@{
            CapturedAt = '2026-08-12T11:00:00-03:00'
            CpuPercent = 35
            MemoryUsedPercent = 65
            SystemDriveFreeGB = 28.5
            StartupEnabledCount = 8
        }

        $result = Compare-PerformanceSnapshot -Before $before -After $after

        $result.CpuPercentDelta | Should -Be -35
        $result.MemoryUsedPercentDelta | Should -Be -15
        $result.SystemDriveFreeGBDelta | Should -Be 8.5
        $result.StartupEnabledCountDelta | Should -Be -4
    }

    It 'preserva null quando uma metrica nao esta disponivel' {
        $result = Compare-PerformanceSnapshot `
            -Before ([pscustomobject]@{ CpuPercent = $null }) `
            -After ([pscustomobject]@{ CpuPercent = 10 })

        $result.CpuPercentDelta | Should -BeNullOrEmpty
    }

    It 'salva snapshot em JSON somente no diretorio de dados do Sync Master' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'dados-performance'
            Mock Registrar-Log {} -ModuleName Otimizacao
            $snapshot = [pscustomobject]@{ SchemaVersion = 1; CapturedAt = '2026-08-12T10:00:00-03:00'; CpuPercent = 20 }

            $path = Save-PerformanceSnapshot -Snapshot $snapshot

            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
            $path | Should -BeLike (Join-Path $env:SYNCMASTER_DATA_DIR 'Reports\Performance\performance_*.json')
            (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).CpuPercent | Should -Be 20
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
}

Describe 'Diagnosticos documentados de energia e memoria virtual' {
    BeforeEach {
        Mock Require-Admin {} -ModuleName Otimizacao
        Mock Registrar-Log {} -ModuleName Otimizacao
        Mock Write-Warning {} -ModuleName Otimizacao
    }

    It 'gera relatorio de energia pelo powercfg e valida o resultado' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'dados-energia'
            Mock powercfg { $global:LASTEXITCODE = 0 } -ModuleName Otimizacao
            Mock Test-Path { $true } -ModuleName Otimizacao

            $path = New-PowerReport -Type Energy -DurationSeconds 30

            $path | Should -BeLike '*power_energy_*.html'
            Should -Invoke powercfg -ModuleName Otimizacao -Times 1 -ParameterFilter {
                $args -contains '/energy' -and $args -contains '/duration' -and $args -contains 30
            }
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }

    It 'nao anuncia relatorio quando powercfg falha' {
        Mock powercfg { $global:LASTEXITCODE = 7 } -ModuleName Otimizacao

        New-PowerReport -Type Battery | Should -BeNullOrEmpty

        Should -Invoke Registrar-Log -ModuleName Otimizacao -Times 0
        Should -Invoke Write-Warning -ModuleName Otimizacao -ParameterFilter { $Message -match 'codigo 7' }
    }

    It 'apenas consulta o pagefile e informa se o Windows o gerencia' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_ComputerSystem') {
                return [pscustomobject]@{ AutomaticManagedPagefile = $true }
            }
            @(
                [pscustomobject]@{ AllocatedBaseSize = 2048; CurrentUsage = 200; PeakUsage = 500 },
                [pscustomobject]@{ AllocatedBaseSize = 1024; CurrentUsage = 100; PeakUsage = 300 }
            )
        } -ModuleName Otimizacao

        $status = Get-PageFileStatus

        $status.AutomaticManaged | Should -BeTrue
        $status.AllocatedMB | Should -Be 3072
        $status.CurrentUsageMB | Should -Be 300
        $status.PeakUsageMB | Should -Be 800
    }
}

Describe 'Microsoft Defender sem exclusoes automaticas' {
    BeforeEach {
        Mock Require-Admin {} -ModuleName Otimizacao
        Mock Registrar-Log {} -ModuleName Otimizacao
        Mock Write-Warning {} -ModuleName Otimizacao
    }

    It 'executa somente a verificacao rapida solicitada' {
        Mock Get-Command { [pscustomobject]@{ Name = 'Start-MpScan' } } -ModuleName Otimizacao
        Mock Start-MpScan {} -ModuleName Otimizacao

        Invoke-DefenderQuickScan -Confirm:$false | Should -BeTrue

        Should -Invoke Start-MpScan -ModuleName Otimizacao -Times 1 -ParameterFilter {
            $ScanType -eq 'QuickScan'
        }
    }

    It 'degrada com aviso quando o Defender nao oferece o comando' {
        Mock Get-Command { $null } -ModuleName Otimizacao
        Mock Start-MpScan {} -ModuleName Otimizacao

        Invoke-DefenderQuickScan -Confirm:$false | Should -BeFalse

        Should -Invoke Start-MpScan -ModuleName Otimizacao -Times 0
        Should -Invoke Require-Admin -ModuleName Otimizacao -Times 0
    }
}

Describe 'Startups preservam itens em falhas e colisoes' {
    BeforeEach {
        Mock Require-Admin {} -ModuleName Otimizacao
        Mock Registrar-Log {} -ModuleName Otimizacao
        Mock Ensure-Dir {} -ModuleName Otimizacao
        Mock Write-Host {} -ModuleName Otimizacao
        Mock Write-Warning {} -ModuleName Otimizacao
    }

    It 'nao renomeia nem remove atalho quando o backup falha' {
        Mock Get-Startups {
            [pscustomobject]@{
                SourceType = 'Folder'; Scope = 'UserFolder'; Enabled = $true
                Name = 'app.lnk'; Command = 'C:\Startup\app.lnk'
            }
        } -ModuleName Otimizacao
        Mock Test-Path { $LiteralPath -eq 'C:\Startup\app.lnk' } -ModuleName Otimizacao
        Mock Move-Item { throw 'destino indisponivel' } -ModuleName Otimizacao
        Mock Rename-Item {} -ModuleName Otimizacao
        Mock Remove-Item {} -ModuleName Otimizacao

        Disable-StartupByNumber -Indexes 1

        Should -Invoke Rename-Item -ModuleName Otimizacao -Times 0
        Should -Invoke Remove-Item -ModuleName Otimizacao -Times 0
    }

    It 'nao sobrescreve atalho ja existente no backup' {
        Mock Get-Startups {
            [pscustomobject]@{
                SourceType = 'Folder'; Scope = 'UserFolder'; Enabled = $true
                Name = 'app.lnk'; Command = 'C:\Startup\app.lnk'
            }
        } -ModuleName Otimizacao
        Mock Test-Path { $true } -ModuleName Otimizacao
        Mock Move-Item {} -ModuleName Otimizacao

        Disable-StartupByNumber -Indexes 1

        Should -Invoke Move-Item -ModuleName Otimizacao -Times 0
    }

    It 'nao sobrescreve valor de Registro ja existente no backup' {
        Mock Get-Startups {
            [pscustomobject]@{
                SourceType = 'Registry'; Scope = 'User'; Enabled = $true
                Name = 'App'; Command = 'novo.exe'; CurrentDir = 'HKCU:\Run'
            }
        } -ModuleName Otimizacao
        Mock Get-ItemProperty { [pscustomobject]@{ App = 'anterior.exe' } } -ModuleName Otimizacao
        Mock New-ItemProperty {} -ModuleName Otimizacao
        Mock Remove-ItemProperty {} -ModuleName Otimizacao

        Disable-StartupByNumber -Indexes 1

        Should -Invoke New-ItemProperty -ModuleName Otimizacao -Times 0
        Should -Invoke Remove-ItemProperty -ModuleName Otimizacao -Times 0
    }

    It 'nao sobrescreve atalho ativo ao reativar backup' {
        Mock Get-Startups {
            [pscustomobject]@{
                SourceType = 'Folder'; Scope = 'UserFolder'; Enabled = $false
                Name = 'app.lnk'; Command = 'C:\Backup\app.lnk'; RestoreDir = 'C:\Startup'
            }
        } -ModuleName Otimizacao
        Mock Test-Path { $true } -ModuleName Otimizacao
        Mock Move-Item {} -ModuleName Otimizacao

        Enable-StartupByNumber -Indexes 1

        Should -Invoke Move-Item -ModuleName Otimizacao -Times 0
    }

    It 'nao sobrescreve valor ativo do Registro ao reativar backup' {
        Mock Get-Startups {
            [pscustomobject]@{
                SourceType = 'Registry'; Scope = 'User'; Enabled = $false
                Name = 'App'; Command = 'backup.exe'
            }
        } -ModuleName Otimizacao
        Mock Get-ItemProperty { [pscustomobject]@{ App = 'ativo.exe' } } -ModuleName Otimizacao
        Mock New-Item {} -ModuleName Otimizacao
        Mock New-ItemProperty {} -ModuleName Otimizacao
        Mock Remove-ItemProperty {} -ModuleName Otimizacao

        Enable-StartupByNumber -Indexes 1

        Should -Invoke New-ItemProperty -ModuleName Otimizacao -Times 0
        Should -Invoke Remove-ItemProperty -ModuleName Otimizacao -Times 0
    }

    It 'move atalho para o backup quando nao ha colisao' {
        Mock Get-Startups {
            [pscustomobject]@{
                SourceType = 'Folder'; Scope = 'UserFolder'; Enabled = $true
                Name = 'app.lnk'; Command = 'C:\Startup\app.lnk'
            }
        } -ModuleName Otimizacao
        Mock Test-Path { $LiteralPath -eq 'C:\Startup\app.lnk' } -ModuleName Otimizacao
        Mock Move-Item {} -ModuleName Otimizacao

        Disable-StartupByNumber -Indexes 1

        Should -Invoke Move-Item -ModuleName Otimizacao -Times 1 -ParameterFilter {
            $LiteralPath -eq 'C:\Startup\app.lnk' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'reativa valor de Registro com escrita terminante quando nao ha colisao' {
        Mock Get-Startups {
            [pscustomobject]@{
                SourceType = 'Registry'; Scope = 'User'; Enabled = $false
                Name = 'App'; Command = 'backup.exe'
            }
        } -ModuleName Otimizacao
        Mock Get-ItemProperty { $null } -ModuleName Otimizacao
        Mock New-Item {} -ModuleName Otimizacao
        Mock New-ItemProperty {} -ModuleName Otimizacao
        Mock Remove-ItemProperty {} -ModuleName Otimizacao

        Enable-StartupByNumber -Indexes 1

        Should -Invoke New-ItemProperty -ModuleName Otimizacao -Times 1 -ParameterFilter {
            $Name -eq 'App' -and $Value -eq 'backup.exe' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Remove-ItemProperty -ModuleName Otimizacao -Times 1
    }
}

Describe 'Get-SyncMasterDataDir' {
    It 'respeita o override $env:SYNCMASTER_DATA_DIR e cria a pasta' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'dados'
            $d = Get-SyncMasterDataDir
            $d | Should -Be (Join-Path $TestDrive 'dados')
            Test-Path $d | Should -BeTrue
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
    It 'cria a subpasta pedida (ex.: Logs)' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'dados2'
            $sub = Get-SyncMasterDataDir -SubPasta 'Logs'
            $sub | Should -Be (Join-Path (Join-Path $TestDrive 'dados2') 'Logs')
            Test-Path $sub | Should -BeTrue
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
    It 'falha se o caminho de dados existente for um arquivo' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'dados-arquivo'
            Set-Content -LiteralPath $env:SYNCMASTER_DATA_DIR -Value 'ocupado'
            { Get-SyncMasterDataDir } | Should -Throw
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
}

Describe 'Start/Stop-SyncMasterLog (transcript de sessao)' {
    It 'cria um sessao_*.log no data dir e fecha com footer' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'logdata'
            $p = Start-SyncMasterLog
            try {
                $p | Should -Not -BeNullOrEmpty
                Test-Path $p | Should -BeTrue
                Split-Path $p -Leaf | Should -BeLike 'sessao_*.log'
            } finally { Stop-SyncMasterLog }
            (Get-Content $p -Raw) | Should -Match 'transcript end'
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
    It 'Start e idempotente (nao abre 2 transcripts)' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'logdata2'
            $p1 = Start-SyncMasterLog
            try { $p2 = Start-SyncMasterLog; $p2 | Should -Be $p1 } finally { Stop-SyncMasterLog }
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
}

Describe 'Ensure-Dir' {
    It 'cria o diretorio (inclusive aninhado)' {
        $p = Join-Path $TestDrive 'a\b\c'
        Ensure-Dir -Path $p
        Test-Path $p | Should -BeTrue
    }
    It 'e idempotente (nao lanca se ja existe)' {
        $p = Join-Path $TestDrive 'x\y'
        Ensure-Dir -Path $p
        { Ensure-Dir -Path $p } | Should -Not -Throw
        Test-Path $p | Should -BeTrue
    }
    It 'falha se o caminho existente for um arquivo' {
        $p = Join-Path $TestDrive 'arquivo'
        Set-Content -LiteralPath $p -Value 'ocupado'
        { Ensure-Dir -Path $p } | Should -Throw
    }
}

Describe 'New-SyncMasterAtalho (Area de Trabalho + Menu Iniciar)' {
    BeforeEach {
        $script:Raiz = Split-Path $PSScriptRoot -Parent
        $script:Base = Join-Path ([IO.Path]::GetTempPath()) ("atalho-" + [guid]::NewGuid().ToString('N'))
        $script:Desktop = Join-Path $script:Base 'Desktop'
        $script:Iniciar = Join-Path $script:Base 'Programs'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
    }

    # O pedido e um atalho nos DOIS lugares: a Area de Trabalho e o clique direto,
    # o Menu Iniciar e a pasta que a busca do Windows indexa.
    It 'cria o atalho nos dois destinos de uma vez' {
        $criados = New-SyncMasterAtalho -Destinos @($script:Desktop, $script:Iniciar)

        @($criados).Count | Should -Be 2
        Test-Path -LiteralPath (Join-Path $script:Desktop 'Sync Master.lnk') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Iniciar 'Sync Master.lnk') | Should -BeTrue
    }

    # O .lnk guarda caminho, nao conteudo: e por isso que atualizar esta copia (git pull
    # ou instalador) nao exige regerar o atalho. Se o alvo deixar de ser o launcher
    # desta copia, essa propriedade morre calada.
    It 'aponta para o launcher desta copia, com o PowerShell do sistema' {
        New-SyncMasterAtalho -Destinos @($script:Desktop) | Out-Null

        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $script:Desktop 'Sync Master.lnk'))
        $lnk.TargetPath | Should -BeLike '*powershell.exe'
        $lnk.Arguments | Should -BeLike ('*' + (Join-Path $script:Raiz 'Sync_Master.ps1') + '*')
        $lnk.WorkingDirectory | Should -Be $script:Raiz
    }

    # Perfil redirecionado ou politica de grupo derruba uma pasta so. Ficar sem o item
    # no Menu Iniciar porque a Area de Trabalho falhou seria perder as duas por uma.
    It 'um destino que falha nao impede o outro' {
        $invalido = Join-Path $script:Base 'in|valido'

        $criados = New-SyncMasterAtalho -Destinos @($invalido, $script:Iniciar) -WarningAction SilentlyContinue

        @($criados).Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $script:Iniciar 'Sync Master.lnk') | Should -BeTrue
    }

    It 'ignora destino vazio que o Windows nao informou' {
        $criados = New-SyncMasterAtalho -Destinos @('', $script:Iniciar) -WarningAction SilentlyContinue

        @($criados).Count | Should -Be 1
    }

    It 'refaz o atalho por cima sem duplicar quando rodado de novo' {
        New-SyncMasterAtalho -Destinos @($script:Desktop) | Out-Null
        New-SyncMasterAtalho -Destinos @($script:Desktop) | Out-Null

        @(Get-ChildItem -LiteralPath $script:Desktop -Filter '*.lnk').Count | Should -Be 1
    }

    It 'nao escreve nada com -WhatIf' {
        New-SyncMasterAtalho -Destinos @($script:Desktop) -WhatIf | Out-Null

        Test-Path -LiteralPath (Join-Path $script:Desktop 'Sync Master.lnk') | Should -BeFalse
    }
}
