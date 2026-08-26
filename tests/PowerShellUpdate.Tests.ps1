# Pester 5 — testes do bootstrap do PowerShell 7 (PowerShellUpdate.psm1).
# Rodar:  Invoke-Pester -Path .\tests
# Alvos: Get-VersionFromReleaseUrl (pura), Get-InstallerInfo (arch), Find-PwshPath e
#        fallback-chain de Get-LatestPowerShellVersion / Install-PowerShell7 (com mocks).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1')             -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\PowerShellUpdate.psm1') -Force -DisableNameChecking
}

Describe 'Get-VersionFromReleaseUrl' {
    It 'extrai a versao de uma URL de release do GitHub' {
        Get-VersionFromReleaseUrl -Url 'https://github.com/PowerShell/PowerShell/releases/tag/v7.5.2' |
            Should -Be '7.5.2'
    }
    It 'extrai so a parte estavel de uma tag preview' {
        Get-VersionFromReleaseUrl -Url 'https://github.com/PowerShell/PowerShell/releases/tag/v7.6.0-preview.2' |
            Should -Be '7.6.0'
    }
    It 'devolve $null para URL sem tag de versao' {
        Get-VersionFromReleaseUrl -Url 'https://aka.ms/powershell-release?tag=stable' |
            Should -BeNullOrEmpty
    }
}

Describe 'Get-LatestPowerShellVersion (fallback-chain)' {
    BeforeEach {
        Mock Start-Sleep {} -ModuleName PowerShellUpdate
    }

    It 'cai na versao pinada quando GitHub e aka.ms estao inacessiveis (-UsePinnedFallback)' {
        Mock Invoke-RestMethod { throw 'bloqueado' } -ModuleName PowerShellUpdate
        Mock Invoke-WebRequest { throw 'bloqueado' } -ModuleName PowerShellUpdate
        $v = Get-LatestPowerShellVersion -UsePinnedFallback 3>$null
        $v | Should -Not -BeNullOrEmpty
        { [version]$v } | Should -Not -Throw   # pinada precisa ser uma versao valida
    }
    It 'sem -UsePinnedFallback devolve $null offline (check de startup nao deve promptar)' {
        Mock Invoke-RestMethod { throw 'bloqueado' } -ModuleName PowerShellUpdate
        Mock Invoke-WebRequest { throw 'bloqueado' } -ModuleName PowerShellUpdate
        Get-LatestPowerShellVersion 3>$null | Should -BeNullOrEmpty
    }
    It 'preview nao usa os fallbacks (so a stable e conhecida)' {
        Mock Invoke-RestMethod { throw 'bloqueado' } -ModuleName PowerShellUpdate
        Mock Invoke-WebRequest { throw 'nao deveria ser chamado' } -ModuleName PowerShellUpdate
        Get-LatestPowerShellVersion -Preview 3>$null | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -ModuleName PowerShellUpdate -Times 0
    }
}

Describe 'Get-InstallerInfo (resolucao de arquitetura)' {
    BeforeEach {
        Mock Invoke-RestMethod { @{ tag_name = 'v7.5.2' } } -ModuleName PowerShellUpdate
    }
    It '64-bit -> win-x64' {
        Mock Get-CimInstance { @{ OSArchitecture = '64-bit' } } -ModuleName PowerShellUpdate
        (Get-InstallerInfo -Version '7.5.2').Url | Should -Match 'PowerShell-7\.5\.2-win-x64\.msi$'
    }
    It 'ARM64 -> win-arm64' {
        Mock Get-CimInstance { @{ OSArchitecture = 'ARM64' } } -ModuleName PowerShellUpdate
        (Get-InstallerInfo -Version '7.5.2').Url | Should -Match 'win-arm64\.msi$'
    }
    It 'arquitetura desconhecida assume x64 (com aviso)' {
        Mock Get-CimInstance { @{ OSArchitecture = 'Itanium' } } -ModuleName PowerShellUpdate
        (Get-InstallerInfo -Version '7.5.2' 3>$null).Url | Should -Match 'win-x64\.msi$'
    }
}

Describe 'Find-PwshPath' {
    It 'prefere o pwsh do PATH quando Get-Command o encontra' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\pf\PowerShell\7\pwsh.exe'; Path = $null } } -ModuleName PowerShellUpdate
        Find-PwshPath | Should -Be 'C:\pf\PowerShell\7\pwsh.exe'
    }
    It 'cai nos caminhos padrao quando o PATH nao tem pwsh' {
        Mock Get-Command { $null } -ModuleName PowerShellUpdate
        Mock Test-Path  { $true }  -ModuleName PowerShellUpdate
        Find-PwshPath | Should -Match 'pwsh\.exe$'
    }
    It 'devolve $null quando nada existe' {
        Mock Get-Command { $null } -ModuleName PowerShellUpdate
        Mock Test-Path  { $false } -ModuleName PowerShellUpdate
        Find-PwshPath | Should -BeNullOrEmpty
    }
}

Describe 'Install-PowerShell7 (cadeia de fallbacks)' {
    It 'para no winget quando ele resolve (nao tenta MSI)' {
        Mock Invoke-WingetInstall        { $true } -ModuleName PowerShellUpdate
        Mock Find-PwshPath               { 'C:\pf\PowerShell\7\pwsh.exe' } -ModuleName PowerShellUpdate
        Mock Start-PowerShellInstallation { }      -ModuleName PowerShellUpdate
        Install-PowerShell7 | Should -BeTrue
        Should -Invoke Start-PowerShellInstallation -ModuleName PowerShellUpdate -Times 0
    }
    It 'sem winget e com admin, tenta o MSI do GitHub' {
        Mock Invoke-WingetInstall        { $false } -ModuleName PowerShellUpdate
        Mock Test-IsAdmin                { $true }  -ModuleName PowerShellUpdate
        Mock Get-LatestPowerShellVersion { '7.5.2' } -ModuleName PowerShellUpdate
        Mock Get-InstallerInfo           { @{ Url = 'https://x/ps.msi'; Path = 'C:\t\ps.msi' } } -ModuleName PowerShellUpdate
        Mock Start-PowerShellInstallation { }       -ModuleName PowerShellUpdate
        Mock Find-PwshPath               { 'C:\pf\PowerShell\7\pwsh.exe' } -ModuleName PowerShellUpdate
        Install-PowerShell7 | Should -BeTrue
        Should -Invoke Start-PowerShellInstallation -ModuleName PowerShellUpdate -Times 1
    }
    It 'sem winget e sem admin, usa o ZIP oficial verificado no perfil do usuario' {
        Mock Invoke-WingetInstall { $false } -ModuleName PowerShellUpdate
        Mock Test-IsAdmin         { $false } -ModuleName PowerShellUpdate
        Mock Get-LatestPowerShellVersion { '7.5.2' } -ModuleName PowerShellUpdate
        Mock Install-PowerShellPortable { $true } -ModuleName PowerShellUpdate
        Mock Find-PwshPath        { $null }  -ModuleName PowerShellUpdate
        Install-PowerShell7 3>$null | Should -BeTrue
        # sem admin, o caminho b (MSI GitHub) nao pode ser tentado
        Should -Invoke Install-PowerShellPortable -ModuleName PowerShellUpdate -Times 1
    }
}

Describe 'Install-PowerShellPortable' {
    It 'instala o ZIP oficial somente quando tamanho e SHA256 conferem' {
        $oldLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'PortableLocalAppData'
        $payload = Join-Path $TestDrive 'portable-payload'
        New-Item -ItemType Directory -Path $payload -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $payload 'pwsh.exe') -Value 'fixture'
        $fixtureZip = Join-Path $TestDrive 'PowerShell.zip'
        Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $fixtureZip
        $sha256 = (Get-FileHash -LiteralPath $fixtureZip -Algorithm SHA256).Hash.ToLowerInvariant()

        Mock Invoke-RestMethod {
            [pscustomobject]@{ assets = @([pscustomobject]@{
                name = 'PowerShell-7.5.2-win-x64.zip'
                browser_download_url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.zip'
                digest = "sha256:$sha256"
                size = (Get-Item -LiteralPath $fixtureZip).Length
            }) }
        } -ModuleName PowerShellUpdate
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $fixtureZip -Destination $OutFile } -ModuleName PowerShellUpdate

        try {
            Install-PowerShellPortable -Version '7.5.2' | Should -BeTrue
            $installedPwsh = Join-Path $env:LOCALAPPDATA 'Microsoft\powershell\pwsh.exe'
            Test-Path $installedPwsh | Should -BeTrue

            Set-Content -LiteralPath $installedPwsh -Value 'preservar'
            $sha256 = '0' * 64
            Install-PowerShellPortable -Version '7.5.2' 3>$null | Should -BeFalse
            Get-Content -LiteralPath $installedPwsh | Should -Be 'preservar'
        }
        finally {
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }
}

Describe 'Install-PowerShellFromMsi (offline)' {
    It 'falha sem lancar quando o MSI nao existe' {
        Install-PowerShellFromMsi -Path (Join-Path $TestDrive 'nao-existe.msi') 3>$null | Should -BeFalse
    }
    It 'aborta quando a assinatura nao e da Microsoft' {
        $fake = Join-Path $TestDrive 'fake.msi'
        Set-Content -Path $fake -Value 'nao sou um msi'
        Mock Get-AuthenticodeSignature { [pscustomobject]@{
            Status = 'NotSigned'
            SignerCertificate = [pscustomobject]@{ Subject = 'CN=Mallory' }
        } } -ModuleName PowerShellUpdate
        Mock Start-Process { throw 'msiexec nao deveria rodar' } -ModuleName PowerShellUpdate
        Install-PowerShellFromMsi -Path $fake 3>$null | Should -BeFalse
        Should -Invoke Start-Process -ModuleName PowerShellUpdate -Times 0
    }
}
