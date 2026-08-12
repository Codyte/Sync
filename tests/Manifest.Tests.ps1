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
}
