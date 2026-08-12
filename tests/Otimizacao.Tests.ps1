# Pester 5 — testes das funcoes PURAS do Sync Master.
# Rodar:  Invoke-Pester -Path .\tests
# Alvos: Parse-Selection (Otimizacao.psm1) e Ensure-Dir (Core.psm1).

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
