# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
# ======================= END NAV INDEX =======================

# Pester 5 — testes das funcoes PURAS do nucleo de sincronizacao (Fase B).
# Rodar:  Invoke-Pester -Path .\tests
# Alvos: Get-RobocopyArgs e Get-RobocopyStatus (Sync.psm1).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Sync.psm1') -Force -DisableNameChecking
}

Describe 'Get-RobocopyArgs' {
    It 'Unilateral seguro usa /E /XO /COPY:DAT e NAO /MIR' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/E'
        $a | Should -Contain '/XO'
        $a | Should -Contain '/COPY:DAT'
        $a | Should -Not -Contain '/MIR'
        $a | Should -Not -Contain '/COPYALL'
    }
    It 'Unilateral -PreservarTudo troca /COPY:DAT por /COPYALL' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -PreservarTudo
        $a | Should -Contain '/COPYALL'
        $a | Should -Not -Contain '/COPY:DAT'
    }
    It 'Espelho usa /MIR /COPYALL e NAO /E /XO' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Espelho -LogPath 'C:\x.log'
        $a | Should -Contain '/MIR'
        $a | Should -Contain '/COPYALL'
        $a | Should -Not -Contain '/E'
        $a | Should -Not -Contain '/XO'
    }
    It '-Simular adiciona /L (dry-run)' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Simular
        $a | Should -Contain '/L'
    }
    It 'sem -Simular NAO inclui /L' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Not -Contain '/L'
    }
    It 'origem/destino sao os 2 primeiros args e o log entra via /LOG+' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\meu.log'
        $a[0] | Should -Be 'C:\o'
        $a[1] | Should -Be 'C:\d'
        ($a -join ' ') | Should -Match '/LOG\+:C:\\meu\.log'
    }
    It 'rejeita Modo invalido (ValidateSet)' {
        { Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo 'Bilateral' -LogPath 'C:\x.log' } | Should -Throw
    }
    It 'inclui /NP sempre (sem progresso por-arquivo)' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/NP'
    }
    It 'default usa /MT:16' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/MT:16'
    }
    It '-Threads troca o valor do /MT' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Threads 32
        $a | Should -Contain '/MT:32'
        $a | Should -Not -Contain '/MT:16'
    }
    It 'default usa só-resumo (/NDL /NFL) e NAO /V' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/NDL'
        $a | Should -Contain '/NFL'
        $a | Should -Not -Contain '/V'
    }
    It '-Detalhado adiciona /V e remove só-resumo' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Detalhado
        $a | Should -Contain '/V'
        $a | Should -Not -Contain '/NDL'
    }
    It 'inclui /BYTES sempre (resumo parseável)' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/BYTES'
    }
    It 'NAO usa /TEE (evita picotar saída do /MT no console/transcript)' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Not -Contain '/TEE'
    }
    It '-IoNaoBufferizado adiciona /J' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -IoNaoBufferizado
        $a | Should -Contain '/J'
    }
    It '-ExcluirDirs injeta /XD seguido dos nomes' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -ExcluirDirs 'Temp','Cache'
        $a | Should -Contain '/XD'
        $a | Should -Contain 'Temp'
        $a | Should -Contain 'Cache'
        ($a -join ' ') | Should -Match '/XD Temp Cache'
    }
    It '-ExcluirArquivos injeta /XF seguido dos padroes' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -ExcluirArquivos 'NTUSER.DAT*','*.tmp'
        $a | Should -Contain '/XF'
        ($a -join ' ') | Should -Match '/XF NTUSER\.DAT\* \*\.tmp'
    }
    It 'sem exclusoes NAO inclui /XD nem /XF' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Not -Contain '/XD'
        $a | Should -Not -Contain '/XF'
    }
    It 'rejeita Threads fora de 1..128 (ValidateRange)' {
        { Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Threads 0 } | Should -Throw
    }
}

Describe 'Test-ParOrigemDestino' {
    BeforeAll {
        $script:oDir = Join-Path ([IO.Path]::GetTempPath()) ("syncpar_o_" + [guid]::NewGuid().ToString('N'))
        $script:dDir = Join-Path ([IO.Path]::GetTempPath()) ("syncpar_d_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:oDir, $script:dDir -Force | Out-Null
    }
    AfterAll {
        Remove-Item -LiteralPath $script:oDir, $script:dDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    It 'aceita origem existente != destino' {
        Test-ParOrigemDestino -Origem $script:oDir -Destino $script:dDir | Should -BeTrue
    }
    It 'rejeita origem inexistente' {
        Test-ParOrigemDestino -Origem (Join-Path $script:oDir 'nao_existe') -Destino $script:dDir -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita origem == destino (mesmo caminho)' {
        Test-ParOrigemDestino -Origem $script:oDir -Destino $script:oDir -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita origem == destino ignorando barra final/case' {
        Test-ParOrigemDestino -Origem $script:oDir -Destino ($script:oDir.ToUpper() + '\') -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita destino DENTRO da origem (aninhado)' {
        $sub = Join-Path $script:oDir 'Backup'
        Test-ParOrigemDestino -Origem $script:oDir -Destino $sub -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita origem DENTRO do destino (aninhado inverso)' {
        $sub = Join-Path $script:dDir 'Sub'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        Test-ParOrigemDestino -Origem $sub -Destino $script:dDir -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'NAO confunde prefixo de nome (Dados vs Dados2)' {
        $a = Join-Path ([IO.Path]::GetTempPath()) ("syncpar_Dados_"  + [guid]::NewGuid().ToString('N'))
        $b = "$a`2"
        New-Item -ItemType Directory -Path $a, $b -Force | Out-Null
        try { Test-ParOrigemDestino -Origem $a -Destino $b | Should -BeTrue }
        finally { Remove-Item -LiteralPath $a, $b -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Resolve-RobocopyTuning' {
    It 'muitos arquivos pequenos => -Rapido + /MT:32' {
        $t = Resolve-RobocopyTuning -FileCount 6000 -TotalBytes (6000 * 50KB) -MaxFileBytes 1MB
        $t.Rapido | Should -BeTrue
        $t.Threads | Should -Be 32
        $t.IoNaoBufferizado | Should -BeFalse
    }
    It 'poucos arquivos grandes (max >= 4GB) => /J + /MT:8' {
        $t = Resolve-RobocopyTuning -FileCount 3 -TotalBytes 12GB -MaxFileBytes 5GB
        $t.IoNaoBufferizado | Should -BeTrue
        $t.Threads | Should -Be 8
        $t.Rapido | Should -BeFalse
    }
    It 'caso medio (>=1000) => /MT:24 sem flags' {
        $t = Resolve-RobocopyTuning -FileCount 1500 -TotalBytes (1500 * 1MB) -MaxFileBytes 5MB
        $t.Threads | Should -Be 24
        $t.Rapido | Should -BeFalse
        $t.IoNaoBufferizado | Should -BeFalse
    }
    It 'arvore pequena => padrao /MT:16' {
        $t = Resolve-RobocopyTuning -FileCount 12 -TotalBytes (12 * 1MB) -MaxFileBytes 2MB
        $t.Threads | Should -Be 16
        $t.Rapido | Should -BeFalse
        $t.IoNaoBufferizado | Should -BeFalse
    }
    It 'arvore vazia nao divide por zero' {
        { Resolve-RobocopyTuning -FileCount 0 -TotalBytes 0 -MaxFileBytes 0 } | Should -Not -Throw
    }
}

Describe 'Measure-ArvoreRapido' {
    BeforeAll {
        $script:mDir = Join-Path ([IO.Path]::GetTempPath()) ("measure_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:mDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:mDir 'a.txt') -Value ('x' * 100)
        Set-Content -Path (Join-Path $script:mDir 'b.txt') -Value ('y' * 250)
    }
    AfterAll { Remove-Item -LiteralPath $script:mDir -Recurse -Force -ErrorAction SilentlyContinue }
    It 'conta arquivos e soma bytes' {
        $m = Measure-ArvoreRapido -Path $script:mDir
        $m.FileCount | Should -Be 2
        $m.TotalBytes | Should -BeGreaterThan 0
        $m.MaxFileBytes | Should -BeGreaterThan 0
    }
    It 'respeita o teto -LimiteArquivos (Truncado)' {
        $m = Measure-ArvoreRapido -Path $script:mDir -LimiteArquivos 1
        $m.FileCount | Should -Be 1
        $m.Truncado | Should -BeTrue
    }
}

Describe 'ConvertTo-TamanhoLegivel' {
    It 'GB' { ConvertTo-TamanhoLegivel -Bytes 2147483648 | Should -Match 'GB$' }
    It 'MB' { ConvertTo-TamanhoLegivel -Bytes 5242880   | Should -Match 'MB$' }
    It 'KB' { ConvertTo-TamanhoLegivel -Bytes 2048      | Should -Match 'KB$' }
    It 'B'  { ConvertTo-TamanhoLegivel -Bytes 512       | Should -Be '512 B' }
}

Describe 'Format-RobocopyResumo' {
    BeforeAll {
        # Saida tipica do robocopy COM /BYTES (contadores em bytes crus -> 6 inteiros por linha).
        $script:logOk = @(
            '   Origem : C:\o\',
            '     Dest : C:\d\',
            '  Iniciado: sexta-feira, 19 de junho de 2026 11:26:52',
            '------------------------------------------------------------------------------',
            '               Total   Copiado  Ignorado  Incompat.    FALHA    Extras',
            'Diretórios:       729       729       594         0         0       176',
            ' Arquivos:       3614       782      2832         0         0        50',
            '    Bytes:  2366541824 386290123 1980251701         0         0 797123456',
            '   Tempos:   0:02:53   0:00:12                       0:00:00   0:00:01'
        )
    }
    It 'devolve tabela com rótulos PT e tempo' {
        $s = Format-RobocopyResumo -Linhas $script:logOk
        $s | Should -Match 'Diretórios:'
        $s | Should -Match 'Arquivos:'
        $s | Should -Match 'Bytes:'
        $s | Should -Match 'Tempo total: 0:02:53'
    }
    It 'converte bytes crus para GB/MB legíveis (nao deixa o inteiro cru)' {
        $s = Format-RobocopyResumo -Linhas $script:logOk
        $s | Should -Match 'GB'
        $s | Should -Not -Match '2366541824'
    }
    It 'NAO confunde o horário do cabeçalho com o tempo total' {
        $s = Format-RobocopyResumo -Linhas $script:logOk
        $s | Should -Not -Match '11:26:52'
    }
    It 'devolve $null quando nao ha bloco de resumo (ex.: sem /BYTES)' {
        Format-RobocopyResumo -Linhas @('linha qualquer','sem contadores') | Should -BeNullOrEmpty
    }
    It 'nao lança com lista vazia' {
        { Format-RobocopyResumo -Linhas @() } | Should -Not -Throw
    }
}

Describe 'Get-ExclusoesPerfil' {
    It 'devolve Dirs e Arquivos nao-vazios' {
        $e = Get-ExclusoesPerfil
        $e.Dirs.Count     | Should -BeGreaterThan 0
        $e.Arquivos.Count | Should -BeGreaterThan 0
    }
    It 'inclui hives travados e caches conhecidos' {
        $e = Get-ExclusoesPerfil
        $e.Arquivos | Should -Contain 'NTUSER.DAT*'
        $e.Dirs     | Should -Contain 'Temp'
    }
}

Describe 'Test-OrigemEhPerfil' {
    It 'pasta com NTUSER.DAT => perfil' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ("perfil_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content -Path (Join-Path $d 'NTUSER.DAT') -Value 'x'
        try { Test-OrigemEhPerfil -Path $d | Should -BeTrue }
        finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'C:\Users (raiz de perfis) => perfil' {
        Test-OrigemEhPerfil -Path (Join-Path $env:SystemDrive 'Users') | Should -BeTrue
    }
    It 'subpasta comum dentro do perfil sem hive => NAO perfil' {
        $d = Join-Path $TestDrive 'Projeto'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Test-OrigemEhPerfil -Path $d | Should -BeFalse
    }
    It 'pasta comum sem hive (fora de C:\Users) => NAO perfil' {
        # Usa a arvore do repo para cobrir uma pasta comum fora de C:\Users.
        $d = Join-Path $root ("comum_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        try { Test-OrigemEhPerfil -Path $d | Should -BeFalse }
        finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Get-RobocopyStatus' {
    It 'exit 0 => SemMudancas' {
        (Get-RobocopyStatus -ExitCode 0).Severidade | Should -Be 'SemMudancas'
    }
    It 'exit 1..7 => Sucesso' {
        (Get-RobocopyStatus -ExitCode 1).Severidade | Should -Be 'Sucesso'
        (Get-RobocopyStatus -ExitCode 7).Severidade | Should -Be 'Sucesso'
    }
    It 'exit >=8 => Erro' {
        (Get-RobocopyStatus -ExitCode 8).Severidade  | Should -Be 'Erro'
        (Get-RobocopyStatus -ExitCode 16).Severidade | Should -Be 'Erro'
    }
    It 'devolve o proprio ExitCode no objeto' {
        (Get-RobocopyStatus -ExitCode 3).ExitCode | Should -Be 3
    }
}

Describe 'Agendar-TarefaSincronizacao (PowerShell da tarefa SYSTEM)' {
    BeforeEach {
        $script:entryAnterior = $env:SYNCMASTER_ENTRY
        $env:SYNCMASTER_ENTRY = Join-Path $root 'Sync_Master.ps1'

        Mock Read-Host { '22:00' } -ModuleName Sync
        Mock Selecionar-DiretorioDaLista { [pscustomobject]@{ Caminho = 'C:\dados' } } -ModuleName Sync
        Mock New-ScheduledTaskTrigger { 'trigger' } -ModuleName Sync
        Mock New-ScheduledTaskPrincipal { 'principal' } -ModuleName Sync
        Mock New-ScheduledTaskAction { 'action' } -ModuleName Sync
        Mock Register-ScheduledTask {} -ModuleName Sync -RemoveParameterType Trigger,Action,Principal
        Mock Registrar-Log {} -ModuleName Sync
        Mock Pause-Script {} -ModuleName Sync
    }

    AfterEach {
        $env:SYNCMASTER_ENTRY = $script:entryAnterior
    }

    It 'nao entrega alias por usuario da Microsoft Store para a conta SYSTEM' {
        $storeAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
        Mock Get-Command { [pscustomobject]@{ Source = $storeAlias } } -ModuleName Sync

        Agendar-TarefaSincronizacao

        Should -Invoke New-ScheduledTaskAction -ModuleName Sync -Times 1 -ParameterFilter {
            $Execute -eq 'powershell.exe'
        }
    }

    It 'mantem o executavel do PowerShell 7 quando a instalacao e de sistema' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\Program Files\PowerShell\7\pwsh.exe' } } -ModuleName Sync

        Agendar-TarefaSincronizacao

        Should -Invoke New-ScheduledTaskAction -ModuleName Sync -Times 1 -ParameterFilter {
            $Execute -eq 'C:\Program Files\PowerShell\7\pwsh.exe'
        }
    }
}
