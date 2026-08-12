# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
# ======================= END NAV INDEX =======================

# Pester 5 - teste local do instalador remoto, sem rede e sem iniciar processos.

Describe 'install.ps1' {
    It 'e ASCII sem BOM e pode ser interpretado pelo pipeline do PowerShell 5.1' {
        $installer = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $bytes = [IO.File]::ReadAllBytes($installer)

        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        $bootstrap = [scriptblock]::Create([Text.Encoding]::ASCII.GetString($bytes))
        { & $bootstrap -WhatIf } | Should -Not -Throw
    }

    It 'instala o pacote completo e preserva os dados do usuario' {
        $oldLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
        $repoRoot = Split-Path $PSScriptRoot -Parent

        $source = Join-Path $TestDrive 'archive\Sync-master'
        New-Item -ItemType Directory -Path (Join-Path $source 'modules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Sync Master.cmd') -Value '@echo off'
        Set-Content -LiteralPath (Join-Path $source 'Sync_Master.ps1') -Value '# launcher'
        Set-Content -LiteralPath (Join-Path $source 'SyncMaster.psd1') -Value '@{}'
        Set-Content -LiteralPath (Join-Path $source 'modules\Core.psm1') -Value '# module'

        $zip = Join-Path $TestDrive 'Sync.zip'
        Compress-Archive -LiteralPath $source -DestinationPath $zip
        $logs = Join-Path $env:LOCALAPPDATA 'SyncMaster\Logs'
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $logs 'preservar.log') -Value 'ok'

        try {
            # Mesmo modelo do IRM: o texto chega sem $PSScriptRoot e vira um scriptblock.
            $bootstrap = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'install.ps1')))
            $commitA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            $commitB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            & $bootstrap -ArchivePath $zip -CommitId $commitA -NoLaunch

            Test-Path (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\Sync_Master.ps1') | Should -BeTrue
            Get-Content (Join-Path $logs 'preservar.log') | Should -Be 'ok'
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() | Should -Be $commitA

            $obsolete = Join-Path $env:LOCALAPPDATA 'SyncMaster\App\obsoleto.txt'
            Set-Content -LiteralPath $obsolete -Value 'remover na atualizacao'
            Mock Start-Process {}
            & $bootstrap -ArchivePath $zip -CommitId $commitA
            Test-Path -LiteralPath $obsolete | Should -BeTrue
            Should -Invoke Start-Process -Times 1

            & $bootstrap -ArchivePath $zip -CommitId $commitB -NoLaunch
            Test-Path -LiteralPath $obsolete | Should -BeFalse
            Get-Content (Join-Path $logs 'preservar.log') | Should -Be 'ok'
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() | Should -Be $commitB
        }
        finally {
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }
}

Describe 'relancamento do Sync Master no PowerShell 7' {
    BeforeAll {
        $mainScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Sync_Master.ps1'
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($mainScript, [ref]$tokens, [ref]$errors)
        $functionAst = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'New-SyncMasterRelaunchArguments'
        }, $true)

        $errors.Count | Should -Be 0
        $functionAst | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }

    It 'preserva caminhos com espacos e apostrofos no comando codificado' {
        $arguments = & {
            [CmdletBinding()]
            param($Acao, $Origem, $Destino, $Modo)

            New-SyncMasterRelaunchArguments `
                -ScriptPath 'C:\Perfil com espaco\Sync_Master.ps1' `
                -BoundParameters $PSBoundParameters
        } `
            -Acao 'Sincronizar' `
            -Origem "C:\Origem com espaco\D'Agua\" `
            -Destino 'D:\Destino com espaco' `
            -Modo 'Bilateral'
        $encoded = ([regex]::Match($arguments, '-EncodedCommand\s+(\S+)$')).Groups[1].Value
        $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))

        $decoded | Should -Be "& 'C:\Perfil com espaco\Sync_Master.ps1' -IsRelaunched -Acao 'Sincronizar' -Origem 'C:\Origem com espaco\D''Agua\' -Destino 'D:\Destino com espaco' -Modo 'Bilateral'"
    }

    It 'nao encerra a sessao inteira do Windows PowerShell' {
        $content = Get-Content -LiteralPath $mainScript -Raw
        $content | Should -Not -Match '\[System\.Environment\]::Exit|Stop-Process\s+-Id\s+\$PID'
    }
}
