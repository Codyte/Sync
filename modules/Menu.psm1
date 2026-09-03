<#
    Menu.psm1 — menu principal data-driven (Fase C do refator).

    Antes: um 'switch' gigante com 18 ramos hardcoded no launcher (texto + dispatch juntos).
    Agora: Get-MenuPrincipal devolve uma TABELA de entradas (dado puro, testavel) e
    Show-MenuPrincipal so RENDERIZA. O DISPATCH continua no launcher (& $entry.Comando),
    porque algumas acoes (Menu-Otimizacao, Criar-App) sao definidas no proprio
    Sync_Master.ps1 e nao sao visiveis de dentro de um modulo.

    Sentinelas de Comando: '__SAIR__' encerra o loop. Demais valores = nome de funcao a invocar.
    Acrescentar um item do menu = uma linha na tabela; nenhum 'switch' a editar.
#>

function Get-MenuPrincipal {
    <#
      .SYNOPSIS  Tabela ordenada de entradas do menu principal (dado puro, sem UI).
      .OUTPUTS   PSCustomObject[]: Id, Texto, Comando, Cor.
    #>
    [CmdletBinding()]
    param()
    @(
        [PSCustomObject]@{ Id='1';   Texto='Sincronização de Arquivos (simular/copiar/espelhar)'; Comando='Iniciar-Sincronizacao';        Cor='Gray'   }
        [PSCustomObject]@{ Id='2';   Texto='Otimização e Reparo do Sistema';                       Comando='Menu-Otimizacao';              Cor='Gray'   }
        [PSCustomObject]@{ Id='3';   Texto='Gerenciamento de Ativação (Oficial)';                  Comando='Menu-Ativacao';                Cor='Gray'   }
        [PSCustomObject]@{ Id='4';   Texto='Gerenciar Diretórios Salvos';                          Comando='Menu-GerenciamentoDiretorios'; Cor='Yellow' }
        [PSCustomObject]@{ Id='5';   Texto='Backup ZIP de Pastas';                                 Comando='Criar-BackupZIP';              Cor='Gray'   }
        [PSCustomObject]@{ Id='6';   Texto='Restaurar Backup ZIP';                                 Comando='Restaurar-BackupZIP';          Cor='Gray'   }
        [PSCustomObject]@{ Id='7';   Texto='Monitoramento de Recursos em Tempo Real';              Comando='Monitorar-Recursos';           Cor='Gray'   }
        [PSCustomObject]@{ Id='8';   Texto='Histórico de Logs de Operação';                        Comando='Visualizar-Logs';              Cor='Gray'   }
        [PSCustomObject]@{ Id='9';   Texto='Agendar Sincronização (Task Scheduler)';               Comando='Agendar-TarefaSincronizacao';  Cor='Gray'   }
        [PSCustomObject]@{ Id='10';  Texto='Verificar Integridade de Arquivos (HASH)';             Comando='Verificar-IntegridadeArquivos';Cor='Gray'   }
        [PSCustomObject]@{ Id='11';  Texto='Diagnóstico de Hardware/Sistema';                      Comando='Diagnostico-Hardware';         Cor='Gray'   }
        [PSCustomObject]@{ Id='12';  Texto='Gerenciar Permissões de Pasta';                        Comando='Permissoes-Pasta';             Cor='Gray'   }
        [PSCustomObject]@{ Id='13';  Texto='Diagnostico de Rede';                                  Comando='Menu-DiagnosticoRede';         Cor='Gray'   }
        [PSCustomObject]@{ Id='15';  Texto='Menu de Atualização do PowerShell';                    Comando='Menu-AtualizacaoPowerShell';   Cor='Gray'   }
        [PSCustomObject]@{ Id='16';  Texto='Instalar Ferramentas de Gerenciamento (winget)';      Comando='Menu-InstalarFerramentas';     Cor='Gray'   }
        [PSCustomObject]@{ Id='17';  Texto='Criar Atalho (Área de Trabalho + Menu Iniciar)';       Comando='Criar-AtalhosSyncMaster';      Cor='Cyan'   }
        [PSCustomObject]@{ Id='APP'; Texto='Criar Aplicativo de Script';                           Comando='Criar-App';                    Cor='Red'    }
        [PSCustomObject]@{ Id='Q';   Texto='Sair';                                                 Comando='__SAIR__';                     Cor='Gray'   }
    )
}

function Show-MenuPrincipal {
    <#
      .SYNOPSIS  Renderiza o cabecalho + a tabela de entradas. So apresentacao.
      .PARAMETER Entradas  Saida de Get-MenuPrincipal (default: a propria).
    #>
    [CmdletBinding()]
    param([PSCustomObject[]]$Entradas = (Get-MenuPrincipal))

    try { Clear-Host } catch { Write-Verbose $_.Exception.Message }  # host sem console (ex.: Pester)
    Write-Host "======================================================" -ForegroundColor DarkGray
    Write-Host "  SUPER FERRAMENTA DE ENGENHARIA - Sync Master" -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor DarkGray
    foreach ($e in $Entradas) {
        $cor = if ($e.Cor) { $e.Cor } else { 'Gray' }
        Write-Host ("{0,3} - {1}" -f $e.Id, $e.Texto) -ForegroundColor $cor
    }
    Write-Host "======================================================" -ForegroundColor DarkGray
}

Export-ModuleMember -Function Get-MenuPrincipal, Show-MenuPrincipal
