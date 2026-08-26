# Pester 5 — catalogo de ferramentas (modules\Ferramentas.psm1).
# Rodar:  Invoke-Pester -Path .\tests
# Get-CatalogoFerramentas e dado puro -> da' para validar a tabela sem chamar winget.

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'SyncMaster.psd1') -Force -DisableNameChecking
    $script:Catalogo = Get-CatalogoFerramentas
}

Describe 'Get-CatalogoFerramentas (tabela)' {
    It 'tem entradas' { $script:Catalogo.Count | Should -BeGreaterThan 0 }

    It 'todo item tem Nome, PacoteId e Descricao nao-vazios' {
        foreach ($f in $script:Catalogo) {
            $f.Nome      | Should -Not -BeNullOrEmpty
            $f.PacoteId  | Should -Not -BeNullOrEmpty
            $f.Descricao | Should -Not -BeNullOrEmpty
        }
    }

    It 'PacoteId tem forma de id winget (Publisher.Pacote) e e unico' {
        foreach ($f in $script:Catalogo) {
            $f.PacoteId | Should -Match '^[\w-]+(\.[\w-]+)+$' -Because "'$($f.PacoteId)' precisa ser um id winget"
        }
        $ids = $script:Catalogo.PacoteId
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }

    # INVARIANTE REAL: Menu-InstalarFerramentas passa Parse-Selection -Max $Catalogo.Count e
    # depois casa por Id. Se os Ids nao forem 1..N contiguos, digitar um numero valido
    # seleciona a ferramenta errada — ou nenhuma — em silencio.
    It 'Ids sao 1..N contiguos (contrato com Parse-Selection)' {
        ($script:Catalogo.Id -join ',') | Should -Be ((1..$script:Catalogo.Count) -join ',')
    }

    It 'todo indice aceito por Parse-Selection casa exatamente uma ferramenta' {
        $max = $script:Catalogo.Count
        foreach ($i in (Parse-Selection -Selection "1-$max" -Max $max)) {
            @($script:Catalogo | Where-Object { $_.Id -eq $i }).Count | Should -Be 1 -Because "indice $i"
        }
    }
}

Describe 'Show-CatalogoFerramentas (render)' {
    It 'nao lanca ao renderizar o catalogo' {
        { Show-CatalogoFerramentas -Catalogo $script:Catalogo 6>$null } | Should -Not -Throw
    }
}

Describe 'Integracao com o menu principal' {
    It 'Menu-InstalarFerramentas esta na tabela do menu principal' {
        (Get-MenuPrincipal | Where-Object Comando -eq 'Menu-InstalarFerramentas').Count | Should -Be 1
    }

    It 'Menu-InstalarFerramentas resolve para uma funcao' {
        Get-Command Menu-InstalarFerramentas -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
