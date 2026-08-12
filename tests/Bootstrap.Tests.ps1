# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
# ======================= END NAV INDEX =======================

# Pester 5 - teste local do instalador remoto, sem rede e sem iniciar processos.

Describe 'install.ps1' {
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
            & $bootstrap -ArchivePath $zip -NoLaunch

            Test-Path (Join-Path $env:LOCALAPPDATA 'SyncMaster\App\Sync_Master.ps1') | Should -BeTrue
            Get-Content (Join-Path $logs 'preservar.log') | Should -Be 'ok'

            $obsolete = Join-Path $env:LOCALAPPDATA 'SyncMaster\App\obsoleto.txt'
            Set-Content -LiteralPath $obsolete -Value 'remover na atualizacao'
            & $bootstrap -ArchivePath $zip -NoLaunch
            Test-Path -LiteralPath $obsolete | Should -BeFalse
            Get-Content (Join-Path $logs 'preservar.log') | Should -Be 'ok'
        }
        finally {
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }
}
