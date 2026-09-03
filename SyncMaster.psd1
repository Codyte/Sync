# SyncMaster.psd1 — manifesto do modulo (Fase A do refator).
# Empacota todos os modulos de dominio num unico ponto de entrada versionado:
#   Import-Module .\SyncMaster.psd1   ->   carrega Core + dominios, exporta as funcoes abaixo.
# Core vem primeiro em NestedModules (dependencia dos demais). O launcher Sync_Master.ps1
# pode importar este manifesto em vez de varrer modules\*.psm1 manualmente.
# Versao do produto e' controlada pelo git (tags); ModuleVersion existe so porque o
# formato .psd1 exige o campo.
@{
    RootModule        = ''
    ModuleVersion     = '1.0.0'
    GUID              = 'b7bf2716-92f9-49ea-b346-31befc2c5630'
    Author            = 'Eng. Carlos Ortiz'
    CompanyName       = 'Codyte'
    Copyright         = '(c) Eng. Carlos Ortiz. Todos os direitos reservados.'
    Description       = 'Super Ferramenta de Engenharia — sincronizacao, backup, otimizacao e diagnostico Windows.'
    PowerShellVersion = '5.1'

    # Core primeiro: os modulos de dominio dependem de Registrar-Log/Test-IsAdmin/etc.
    NestedModules = @(
        'modules\Core.psm1',
        'modules\Menu.psm1',
        'modules\Otimizacao.psm1',
        'modules\Sync.psm1',
        'modules\Backup.psm1',
        'modules\Arquivos.psm1',
        'modules\Hardware.psm1',
        'modules\Rede.psm1',
        'modules\Ativacao.psm1',
        'modules\PowerShellUpdate.psm1',
        'modules\Ferramentas.psm1'
    )

    FunctionsToExport = @(
        # Core
        'Get-SyncMasterDataDir','Start-SyncMaster','Start-SyncMasterLog','Stop-SyncMasterLog','Pause-Script',
        'Confirm-Action','Registrar-Log','Visualizar-Logs','Ensure-Dir','Test-IsAdmin','Require-Admin',
        # Menu (data-driven, Fase C)
        'Get-MenuPrincipal','Show-MenuPrincipal',
        # Otimizacao
        'Pause-Local','Clean-Temp','Get-Startups','Parse-Selection','Disable-StartupByNumber','Enable-StartupByNumber',
        'Menu-Startups','Get-PerformanceSnapshot','Save-PerformanceSnapshot','Compare-PerformanceSnapshot',
        'Compare-LatestPerformanceSnapshots','Get-PageFileStatus','New-PowerReport','Invoke-DefenderQuickScan',
        'Invoke-DefenderPerformanceAnalysis','Menu-DefenderPerformance','Invoke-StorageOptimization',
        'Storage-Maintenance','Set-PowerPlan','Power-CPU-Tune',
        # Sync
        'Salvar-Diretorios','Menu-GerenciamentoDiretorios','Selecionar-DiretorioDaLista','ObterCaminhoPasta',
        'Iniciar-Sincronizacao','Resolve-ShareToDiskInfoV2','VerificarEspacoEmDiscoV2','Get-TamanhoPastaBytesV2',
        'Comparar-EspacoVsOrigemV2','Get-RobocopyArgs','Get-RobocopyStatus','Resolve-RobocopyTuning','Measure-ArvoreRapido','ConvertTo-TamanhoLegivel','Format-RobocopyResumo','Show-RobocopyResultado','Get-ExclusoesPerfil','Test-OrigemEhPerfil','Test-ParOrigemDestino',
        'Start-RobocopyUnilateralSeguro','Start-RobocopyEspelho','Iniciar-SincronizacaoV2','Agendar-TarefaSincronizacao',
        # Backup
        'Get-ZipBackupPath','Invoke-ZipBackup','Invoke-ZipRestore','Criar-BackupZIP','Restaurar-BackupZIP',
        # Arquivos
        'Remove-ToRecycleBin','Menu-GerenciamentoArquivos','Encontrar-ArquivosDuplicados',
        'Verificar-IntegridadeArquivos','Permissoes-Pasta',
        # Hardware
        'Get-CpuRapido','Get-MemUsoMB','Get-DiscosInfo','Merge-DiscoFisico','Monitorar-Recursos','Diagnostico-Hardware','Get-CpuUsageRobusto',
        # Rede
        'Menu-DiagnosticoRede','Test-TcpPort','Testar-PortaTCP','Ping-Sweep','ConvertFrom-PortSpec','Scan-PortasTCP','Scan-ARP',
        'Descobrir-Hostnames','Whois-Lookup','Scan-Servicos','Mostrar-Netstat','Instalar-e-Testar-Speedtest',
        'Menu-Rede','Configurar-TcpAutoTuning',
        # Ativacao
        'Menu-Ativacao','Mostrar-StatusAtivacao','Instalar-ChaveProduto','Ativar-Windows',
        # PowerShellUpdate
        'Get-LatestPowerShellVersion','Start-PowerShellInstallation','Get-InstallerInfo','Invoke-WingetInstall',
        'Find-PwshPath','Install-PowerShell7','Menu-AtualizacaoPowerShell',
        # Ferramentas (instalacao via winget)
        'Get-CatalogoFerramentas','Show-CatalogoFerramentas','Install-Ferramenta','Menu-InstalarFerramentas'
    )

    AliasesToExport = @('Clear-Temp','Restore-PontoRestauracao')
    CmdletsToExport = @()
    VariablesToExport = @()
}
