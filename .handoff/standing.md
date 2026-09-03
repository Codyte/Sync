# Standing decisions · Sync Master

- Público-alvo: Windows 10 e Windows 11 desktop comuns em x64, ambos tratados como alvos de primeira classe.
- Fora de escopo: Windows Server, Server Core, Windows legado fora de suporte e cenários raros que limitem o desenvolvimento ou tenham pouco retorno.
- PowerShell 7 é o runtime preferencial; Windows PowerShell 5.1 precisa sustentar apenas bootstrap, detecção, instalação e relançamento confiáveis, além dos fluxos automatizados já deliberadamente compatíveis.
- Priorizar confiabilidade e utilidade prática, não compatibilidade perfeita: recursos opcionais devem degradar com aviso claro, sem derrubar o restante da ferramenta.
- Auditar pelo risco e grafo de chamadas, começando nas dependências compartilhadas e funções com efeitos externos; não percorrer mecanicamente pela ordem do arquivo.
- Mudanças pequenas, cada correção com teste de regressão; não ampliar suporte a plataformas sem evidência de retorno.
- Por solicitação explícita do mantenedor em 2026-09-03, preservar a opção oculta `4` (`Ati`) do menu de ativação, inclusive o download confirmado do Microsoft Activation Scripts. Decisão do dono, 2026-08-26, revertendo a remoção da auditoria de 12/08 (`ec51ba1`): a opção continua oculta no menu, a função não é exportada (nem no manifesto nem no `Export-ModuleMember`), e a execução só ocorre com SHA256 + `Confirm-Action` via `scriptblock`, nunca `Invoke-Expression`. Esta é uma exceção específica e não reabre pontes genéricas para execução remota; consequência aceita: o repo é público e publica esse downloader.
