# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L288   Pause-Script
#   L295   Invoke-ps2exe
#   L316   Invoke-ps2exe
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
            $sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
            & $bootstrap -ArchivePath $zip -CommitId $commitA -ExpectedSha256 $sha256 -NoLaunch

            Test-Path (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\Sync_Master.ps1') | Should -BeTrue
            Get-Content (Join-Path $logs 'preservar.log') | Should -Be 'ok'
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() | Should -Be $commitA

            $obsolete = Join-Path $env:LOCALAPPDATA 'SyncMaster\App\obsoleto.txt'
            Set-Content -LiteralPath $obsolete -Value 'remover na atualizacao'
            Mock Start-Process {}
            & $bootstrap -ArchivePath $zip -CommitId $commitA
            Test-Path -LiteralPath $obsolete | Should -BeTrue
            Should -Invoke Start-Process -Times 1

            { & $bootstrap -ArchivePath $zip -CommitId $commitB -ExpectedSha256 ('0' * 64) -NoLaunch } |
                Should -Throw '*SHA256*'
            Test-Path -LiteralPath $obsolete | Should -BeTrue
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() | Should -Be $commitA

            & $bootstrap -ArchivePath $zip -CommitId $commitB -ExpectedSha256 $sha256 -NoLaunch
            Test-Path -LiteralPath $obsolete | Should -BeFalse
            Get-Content (Join-Path $logs 'preservar.log') | Should -Be 'ok'
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() | Should -Be $commitB
            Test-Path (Join-Path $env:LOCALAPPDATA 'SyncMaster\App.previous\obsoleto.txt') | Should -BeTrue
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App.previous\.syncmaster-commit')).Trim() | Should -Be $commitA
        }
        finally {
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }

    It 'instala a release estavel somente quando o digest do asset confere' {
        $oldLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'ReleaseLocalAppData'
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $source = Join-Path $TestDrive 'release\SyncMaster'
        New-Item -ItemType Directory -Path (Join-Path $source 'modules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Sync Master.cmd') -Value '@echo off'
        Set-Content -LiteralPath (Join-Path $source 'Sync_Master.ps1') -Value '# launcher'
        Set-Content -LiteralPath (Join-Path $source 'SyncMaster.psd1') -Value '@{}'
        Set-Content -LiteralPath (Join-Path $source 'modules\Core.psm1') -Value '# module'
        $fixtureZip = Join-Path $TestDrive 'Release.zip'
        Compress-Archive -LiteralPath $source -DestinationPath $fixtureZip
        $sha256 = (Get-FileHash -LiteralPath $fixtureZip -Algorithm SHA256).Hash.ToLowerInvariant()

        Mock Invoke-RestMethod {
            [pscustomobject]@{
                tag_name  = 'v1.2.3'
                draft     = $false
                prerelease = $false
                immutable = $true
                assets    = @([pscustomobject]@{
                    name = 'SyncMaster.zip'
                    browser_download_url = 'https://github.com/Codyte/Sync/releases/download/v1.2.3/SyncMaster.zip'
                    digest = "sha256:$sha256"
                    size = (Get-Item -LiteralPath $fixtureZip).Length
                })
            }
        }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $fixtureZip -Destination $OutFile }

        try {
            $bootstrap = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'install.ps1')))
            & $bootstrap -NoLaunch

            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() |
                Should -Be 'release:v1.2.3'
            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://github.com/Codyte/Sync/releases/download/v1.2.3/SyncMaster.zip'
            }
        }
        finally {
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }

    It 'repete uma consulta transitoria e instala quando a segunda tentativa funciona' {
        $oldLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'RetryLocalAppData'
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $source = Join-Path $TestDrive 'retry\SyncMaster'
        New-Item -ItemType Directory -Path (Join-Path $source 'modules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Sync Master.cmd') -Value '@echo off'
        Set-Content -LiteralPath (Join-Path $source 'Sync_Master.ps1') -Value '# launcher'
        Set-Content -LiteralPath (Join-Path $source 'SyncMaster.psd1') -Value '@{}'
        Set-Content -LiteralPath (Join-Path $source 'modules\Core.psm1') -Value '# module'
        $fixtureZip = Join-Path $TestDrive 'Retry.zip'
        Compress-Archive -LiteralPath $source -DestinationPath $fixtureZip
        $sha256 = (Get-FileHash -LiteralPath $fixtureZip -Algorithm SHA256).Hash.ToLowerInvariant()
        $script:releaseAttempts = 0

        Mock Start-Sleep {}
        Mock Invoke-RestMethod {
            $script:releaseAttempts++
            if ($script:releaseAttempts -eq 1) { throw 'falha transitoria' }
            [pscustomobject]@{
                tag_name = 'v1.2.4'; draft = $false; prerelease = $false; immutable = $true
                assets = @([pscustomobject]@{
                    name = 'SyncMaster.zip'
                    browser_download_url = 'https://github.com/Codyte/Sync/releases/download/v1.2.4/SyncMaster.zip'
                    digest = "sha256:$sha256"
                    size = (Get-Item -LiteralPath $fixtureZip).Length
                })
            }
        }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $fixtureZip -Destination $OutFile }

        try {
            $bootstrap = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'install.ps1')))
            & $bootstrap -NoLaunch
            $script:releaseAttempts | Should -Be 2
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() |
                Should -Be 'release:v1.2.4'
        }
        finally {
            $env:LOCALAPPDATA = $oldLocalAppData
            Remove-Variable -Name releaseAttempts -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'restaura a versao anterior quando o launcher nao pode ser iniciado' {
        $oldLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'RollbackLocalAppData'
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $source = Join-Path $TestDrive 'rollback\SyncMaster'
        New-Item -ItemType Directory -Path (Join-Path $source 'modules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Sync Master.cmd') -Value '@echo off'
        Set-Content -LiteralPath (Join-Path $source 'Sync_Master.ps1') -Value '# launcher'
        Set-Content -LiteralPath (Join-Path $source 'SyncMaster.psd1') -Value '@{}'
        Set-Content -LiteralPath (Join-Path $source 'modules\Core.psm1') -Value '# module'
        $fixtureZip = Join-Path $TestDrive 'Rollback.zip'
        Compress-Archive -LiteralPath $source -DestinationPath $fixtureZip
        $sha256 = (Get-FileHash -LiteralPath $fixtureZip -Algorithm SHA256).Hash
        $bootstrap = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'install.ps1')))

        try {
            & $bootstrap -ArchivePath $fixtureZip -CommitId ('a' * 40) -ExpectedSha256 $sha256 -NoLaunch
            Mock Start-Process { throw 'falha simulada ao abrir' }
            { & $bootstrap -ArchivePath $fixtureZip -CommitId ('b' * 40) -ExpectedSha256 $sha256 } |
                Should -Throw '*falha simulada*'
            (Get-Content (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\.syncmaster-commit')).Trim() |
                Should -Be ('a' * 40)
        }
        finally {
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }

    It 'publica o asset esperado sem action de terceiros' {
        $root = Split-Path $PSScriptRoot -Parent
        $workflow = Get-Content -Raw -LiteralPath (Join-Path $root '.github\workflows\release.yml')

        $workflow | Should -Match 'gh api'
        $workflow | Should -Match 'gh release create'
        $workflow | Should -Match 'SyncMaster\.zip'
        $workflow | Should -Not -Match '(?m)^\s*uses:'
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

        $startFunctionAst = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Start-SyncMasterInPowerShell7'
        }, $true)
        $startFunctionAst | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($startFunctionAst.Extent.Text))
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

    It 'usa -File no CMD e deixa a elevacao segura para o script' {
        $cmd = Get-Content -Raw -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Sync Master.cmd')
        $cmd | Should -Match '(?i)-File\s+"%~dp0Sync_Master\.ps1"'
        $cmd | Should -Not -Match '(?i)Set-Location.*%~dp0'
    }

    It 'pede UAC com RunAs e usa a pasta do script como diretorio de trabalho' {
        Mock Start-Process { [pscustomobject]@{ Id = 1 } }
        $scriptPath = 'C:\Pasta com espaco\Sync_Master.ps1'

        Start-SyncMasterInPowerShell7 `
            -PwshPath 'C:\Program Files\PowerShell\7\pwsh.exe' `
            -ScriptPath $scriptPath `
            -BoundParameters @{} `
            -Elevate | Out-Null

        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $Verb -eq 'RunAs' -and $WorkingDirectory -eq 'C:\Pasta com espaco'
        }
    }
}

Describe 'Criar-App' {
    BeforeAll {
        $mainScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Sync_Master.ps1'
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($mainScript, [ref]$tokens, [ref]$errors)
        $functionAst = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Criar-App'
        }, $true)

        $errors.Count | Should -Be 0
        $functionAst | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($functionAst.Extent.Text))
        function Pause-Script {}
    }

    It 'resolve Invoke-ps2exe sem caminho versionado e publica somente a saida criada' {
        $source = Join-Path $TestDrive 'Meu Script.ps1'
        $expected = [IO.Path]::ChangeExtension($source, '.exe')
        Set-Content -LiteralPath $source -Value 'Write-Host ok'
        function Invoke-ps2exe {
            [CmdletBinding()]
            param($inputFile, $outputFile)
            Set-Content -LiteralPath $outputFile -Value "compilado:$inputFile"
        }

        try {
            Criar-App -ScriptPath $source
            Test-Path -LiteralPath $expected -PathType Leaf | Should -BeTrue
            Get-Content -LiteralPath $expected | Should -Be "compilado:$source"
        }
        finally {
            Remove-Item Function:\Invoke-ps2exe -ErrorAction SilentlyContinue
        }
    }

    It 'preserva o executavel anterior quando o conversor falha' {
        $source = Join-Path $TestDrive 'Falha.ps1'
        $expected = [IO.Path]::ChangeExtension($source, '.exe')
        Set-Content -LiteralPath $source -Value 'Write-Host ok'
        Set-Content -LiteralPath $expected -Value 'anterior'
        function Invoke-ps2exe { throw 'falha simulada' }

        try {
            Criar-App -ScriptPath $source -ErrorAction SilentlyContinue
            Get-Content -LiteralPath $expected | Should -Be 'anterior'
        }
        finally {
            Remove-Item Function:\Invoke-ps2exe -ErrorAction SilentlyContinue
        }
    }
}
