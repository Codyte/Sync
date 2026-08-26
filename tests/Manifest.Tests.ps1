# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
# ======================= END NAV INDEX =======================

# Pester 5 — Fase A: manifesto SyncMaster.psd1.
# Rodar:  Invoke-Pester -Path .\tests
# Garante que o ponto de entrada unico carrega Core + dominios e exporta as funcoes-chave.

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:Manifesto = Join-Path $root 'SyncMaster.psd1'
    Import-Module $script:Manifesto -Force -DisableNameChecking
}

Describe 'SyncMaster.psd1 (manifesto)' {
    It 'e um manifesto valido' {
        { Test-ModuleManifest -Path $script:Manifesto -ErrorAction Stop } | Should -Not -Throw
    }
    It 'expoe funcao do Core: <_>' -ForEach @(
        'Registrar-Log','Test-IsAdmin','Get-SyncMasterDataDir','Pause-Script','Start-SyncMasterLog'
    ) {
        Get-Command $_ -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    It 'expoe funcao de dominio: <_>' -ForEach @(
        'Iniciar-Sincronizacao','Criar-BackupZIP','Monitorar-Recursos','Ping-Sweep',
        'Menu-Ativacao','Get-RobocopyArgs','Parse-Selection','Verificar-IntegridadeArquivos',
        'Install-PowerShell7','Find-PwshPath'
    ) {
        Get-Command $_ -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'nao exporta o ativador remoto' {
        $manifest = Import-PowerShellDataFile -Path $script:Manifesto
        $manifest.FunctionsToExport | Should -Not -Contain 'Ativar-Crack'
        # O ativador fica no modulo (decisao do dono do repo, 2026-08-26), mas continua PRIVADO:
        # fora do manifesto e fora do Export-ModuleMember. Antes daqui o teste exigia que nem o
        # nome aparecesse no arquivo.
        $manifest.FunctionsToExport | Should -Not -Contain 'Ati'
        (Get-Content (Join-Path $root 'modules\Ativacao.psm1') -Raw) | Should -Not -Match 'Export-ModuleMember[^\r\n]*\bAti\b'
    }

    It 'nao exporta nem anuncia clonagem bruta por dd' {
        $manifest = Import-PowerShellDataFile -Path $script:Manifesto
        $manifest.FunctionsToExport | Should -Not -Contain 'Clonar-Disco'
        Get-Content (Join-Path $root 'modules\Backup.psm1') -Raw | Should -Not -Match '(?i)\bClonar-Disco\b'
        (Get-MenuPrincipal).Comando | Should -Not -Contain 'Clonar-Disco'
    }

    It 'nao exporta pseudo-otimizacao de banda reservada' {
        $manifest = Import-PowerShellDataFile -Path $script:Manifesto
        $manifest.FunctionsToExport | Should -Not -Contain 'Otimizar-QoS'
        Get-Content (Join-Path $root 'modules\Rede.psm1') -Raw | Should -Not -Match '(?i)\bOtimizar-QoS\b'
    }

    It 'exporta apenas as rotinas uteis da area de otimizacao' {
        $manifest = Import-PowerShellDataFile -Path $script:Manifesto
        foreach ($nome in 'Get-PerformanceSnapshot','Compare-PerformanceSnapshot','New-PowerReport',
            'Invoke-DefenderQuickScan','Invoke-StorageOptimization','Set-PowerPlan','Clean-Temp','Menu-Startups') {
            $manifest.FunctionsToExport | Should -Contain $nome
        }
        foreach ($nome in 'Set-DWord','Tasks-Noise','SearchIndexer-Toggle','Disk-SMART','Toggle-PowerPlan') {
            $manifest.FunctionsToExport | Should -Not -Contain $nome
        }
    }
}
