# Standing decisions · Sync Master

- Público-alvo: Windows 10 e Windows 11 desktop comuns em x64, ambos tratados como alvos de primeira classe.
- Fora de escopo: Windows Server, Server Core, Windows legado fora de suporte e cenários raros que limitem o desenvolvimento ou tenham pouco retorno.
- PowerShell 7 é o runtime preferencial; Windows PowerShell 5.1 precisa sustentar apenas bootstrap, detecção, instalação e relançamento confiáveis, além dos fluxos automatizados já deliberadamente compatíveis.
- Priorizar confiabilidade e utilidade prática, não compatibilidade perfeita: recursos opcionais devem degradar com aviso claro, sem derrubar o restante da ferramenta.
- Auditar pelo risco e grafo de chamadas, começando nas dependências compartilhadas e funções com efeitos externos; não percorrer mecanicamente pela ordem do arquivo.
- Mudanças pequenas, cada correção com teste de regressão; não ampliar suporte a plataformas sem evidência de retorno.
- O ativador remoto (opção 4 do `Menu-Ativacao`, função `Ati`, MAS/`get.activated.win`) **fica** — decisão do dono, 2026-08-26, revertendo a remoção da auditoria de 12/08 (`ec51ba1`). Os testes travam o **contorno**, não a ausência: opção não anunciada no menu, função não exportada (nem no manifesto nem no `Export-ModuleMember`), e execução só com SHA256 + `Confirm-Action` via `scriptblock`, nunca `Invoke-Expression`. Consequência aceita: o repo é público e publica esse downloader.
