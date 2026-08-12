# Standing decisions · Sync Master

- Público-alvo: Windows desktop comum, principalmente Windows 11 x64; Windows 10 suportado entra quando não aumentar materialmente o esforço.
- Fora de escopo: Windows Server, Server Core, Windows legado fora de suporte e cenários raros que limitem o desenvolvimento ou tenham pouco retorno.
- PowerShell 7 é o runtime preferencial; Windows PowerShell 5.1 precisa sustentar apenas bootstrap, detecção, instalação e relançamento confiáveis, além dos fluxos automatizados já deliberadamente compatíveis.
- Priorizar confiabilidade e utilidade prática, não compatibilidade perfeita: recursos opcionais devem degradar com aviso claro, sem derrubar o restante da ferramenta.
- Auditar pelo risco e grafo de chamadas, começando nas dependências compartilhadas e funções com efeitos externos; não percorrer mecanicamente pela ordem do arquivo.
- Mudanças pequenas, cada correção com teste de regressão; não ampliar suporte a plataformas sem evidência de retorno.
