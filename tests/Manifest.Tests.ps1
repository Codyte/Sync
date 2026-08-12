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

    It 'nao exporta nem mantem ativador remoto' {
        $manifest = Import-PowerShellDataFile -Path $script:Manifesto
        $manifest.FunctionsToExport | Should -Not -Contain 'Ativar-Crack'
        Get-Content (Join-Path $root 'modules\Ativacao.psm1') -Raw | Should -Not -Match '(?i)\bAtivar-Crack\b'
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
}
