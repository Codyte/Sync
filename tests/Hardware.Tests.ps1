# Pester 5 — Fase B: nucleo puro do dominio Hardware (modules\Hardware.psm1).
# Rodar:  Invoke-Pester -Path .\tests
# Alvo: Merge-DiscoFisico (correlacao Win32_DiskDrive x Get-PhysicalDisk, sem CIM/UI).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1')     -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Hardware.psm1') -Force -DisableNameChecking

    # Discos sinteticos (imitam Win32_DiskDrive selecionado) e PhysicalDisks.
    $script:Base = @(
        [pscustomobject]@{ Model='Samsung SSD 980'; InterfaceType='SCSI'; 'Tamanho (GB)'=931.5; SerialNumber='SER-AAA'; FirmwareRevision='1B2QEXM7' }
        [pscustomobject]@{ Model='WDC WD10EZEX';     InterfaceType='IDE';  'Tamanho (GB)'=931.5; SerialNumber='SER-BBB'; FirmwareRevision='80.00A80' }
    )
    $script:Pd = @(
        [pscustomobject]@{ FriendlyName='Samsung SSD 980'; SerialNumber='SER-AAA'; MediaType='SSD'; BusType='NVMe' }
        [pscustomobject]@{ FriendlyName='WDC WD10EZEX';     SerialNumber='SER-BBB'; MediaType='HDD'; BusType='SATA' }
    )
}

Describe 'Merge-DiscoFisico' {
    It 'enriquece por SerialNumber: MediaType e BusType vem do PhysicalDisk' {
        $r = Merge-DiscoFisico -Base $script:Base -PhysicalDisks $script:Pd
        ($r | Where-Object SerialNumber -eq 'SER-AAA').MediaType | Should -Be 'SSD'
        ($r | Where-Object SerialNumber -eq 'SER-AAA').Interface | Should -Be 'NVMe'
        ($r | Where-Object SerialNumber -eq 'SER-BBB').MediaType | Should -Be 'HDD'
    }
    It 'preserva 1 objeto por disco de base' {
        (Merge-DiscoFisico -Base $script:Base -PhysicalDisks $script:Pd).Count | Should -Be 2
    }
    It 'sem casamento: MediaType nulo e Interface cai no InterfaceType original' {
        $r = Merge-DiscoFisico -Base $script:Base -PhysicalDisks @()
        ($r | Where-Object SerialNumber -eq 'SER-AAA').MediaType | Should -BeNullOrEmpty
        ($r | Where-Object SerialNumber -eq 'SER-AAA').Interface | Should -Be 'SCSI'
    }
    It 'casa por FriendlyName quando o serial nao bate' {
        $pd2 = @([pscustomobject]@{ FriendlyName='Samsung SSD 980'; SerialNumber='OUTRO'; MediaType='SSD'; BusType='NVMe' })
        $r = Merge-DiscoFisico -Base @($script:Base[0]) -PhysicalDisks $pd2
        $r.MediaType | Should -Be 'SSD'
    }
    It 'base vazia -> nenhum objeto' {
        (Merge-DiscoFisico -Base @() -PhysicalDisks $script:Pd).Count | Should -Be 0
    }
}

Describe 'Monitorar-Recursos valida parametros antes do loop' {
    It 'rejeita ciclo de disco zero e intervalo agressivo' {
        $cmd = Get-Command Monitorar-Recursos
        $ciclos = $cmd.Parameters['CiclosDisco'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
        $intervalo = $cmd.Parameters['IntervaloMs'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

        $ciclos.MinRange | Should -Be 1
        $intervalo.MinRange | Should -Be 50
    }
}
