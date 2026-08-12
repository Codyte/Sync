[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ReportJson,
  [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference = 'Stop'

function N([string]$s){ if($null -eq $s){ return '' }; return $s.Trim().Normalize([Text.NormalizationForm]::FormC) }

if(-not (Test-Path $ReportJson)){ throw "ReportJson not found: $ReportJson" }
if(-not (Test-Path $OutputRoot)){ throw "OutputRoot not found: $OutputRoot" }

$flow = Get-Content -Path $ReportJson | ConvertFrom-Json

# Global sanity for approved baselines
$badQuotes = $flow | Where-Object { (N $_.Title) -match '"$' }
if($badQuotes){ throw "Found titles ending with quote." }

# ---------------------------------------------------------------------------
# Path 2 validation (approved)
# ---------------------------------------------------------------------------
$root2 = $flow | Where-Object { $_.Parent -eq '__ROOT__' -and $_.Key -eq '2' } | Select-Object -First 1
if($null -eq $root2){ throw 'Missing root option 2' }
if((N $root2.Title) -notlike 'Otimização e Reparo do Sistema*'){ throw "Root 2 title mismatch: '$($root2.Title)'" }
if((N $root2.Function) -ne 'Menu-Otimizacao'){ throw "Root 2 function mismatch: '$($root2.Function)'" }
if((N $root2.Type) -ne 'Menu'){ throw "Root 2 type mismatch: '$($root2.Type)'" }

$opt6 = $flow | Where-Object { $_.Parent -eq 'Menu-Otimizacao' -and $_.Key -eq '6' } | Select-Object -First 1
if($null -eq $opt6){ throw 'Missing Menu-Otimizacao option 6' }
if((N $opt6.Function) -ne 'Menu-GerenciarAgentes'){ throw "Menu-Otimizacao key 6 function mismatch: '$($opt6.Function)'" }
if($flow | Where-Object { $_.Parent -eq 'Menu-Avancado' -or $_.Function -eq 'Menu-Avancado' }){
  throw 'Removed advanced optimization menu is still present in the flow.'
}

# ---------------------------------------------------------------------------
# Path 13 validation (approved)
# ---------------------------------------------------------------------------
$root13 = $flow | Where-Object { $_.Parent -eq '__ROOT__' -and $_.Key -eq '13' } | Select-Object -First 1
if($null -eq $root13){ throw 'Missing root option 13' }
if((N $root13.Title) -ne 'Diagnostico de Rede'){ throw "Root 13 title mismatch: '$($root13.Title)'" }
if((N $root13.Function) -ne 'Menu-DiagnosticoRede'){ throw "Root 13 function mismatch: '$($root13.Function)'" }
if((N $root13.Type) -ne 'Menu'){ throw "Root 13 type mismatch: '$($root13.Type)'" }

$expected = @(
  @{ Key='1'; Title='Testar Porta TCP Específica'; Type='Action' },
  @{ Key='2'; Title='Ping Sweep'; Type='Action' },
  @{ Key='3'; Title='Scan de Faixa de Portas TCP'; Type='Action' },
  @{ Key='4'; Title='Scan de Dispositivos na Rede'; Type='Action' },
  @{ Key='5'; Title='Descobrir Nomes de Host'; Type='Action' },
  @{ Key='6'; Title='Consulta WHOIS/DNS de um Domínio'; Type='Action' },
  @{ Key='7'; Title='Scan de Serviços Comuns em um Host'; Type='Action' },
  @{ Key='8'; Title='Ver Conexões de Rede Ativas'; Type='Action' },
  @{ Key='9'; Title='Testar Velocidade da Internet'; Type='Action' },
  @{ Key='Q'; Title='Voltar ao Menu Principal'; Type='Return' }
)

$networkItems = $flow | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' }

foreach($e in $expected){
  $item = $networkItems | Where-Object { (N $_.Key).ToUpper() -eq (N $e.Key).ToUpper() } | Select-Object -First 1
  if($null -eq $item){ throw "Missing Menu-DiagnosticoRede option: $($e.Key)" }
  if((N $item.Title) -like 'Opcao *'){ throw "Fallback title in Menu-DiagnosticoRede key=$($e.Key): $($item.Title)" }
  if((N $item.Title) -match '"$'){ throw "Trailing quote in Menu-DiagnosticoRede key=$($e.Key): $($item.Title)" }
  if((N $item.Type) -ne (N $e.Type)){ throw "Type mismatch key=$($e.Key): got '$($item.Type)' expected '$($e.Type)'" }
  if($e.Key -ne 'Q' -and (N $item.Function) -notlike 'Invoke-FlowAction-*'){ throw "Expected wrapper function key=$($e.Key), got '$($item.Function)'" }
}

# Helper functions must not be primary targets for final menu actions
$blockedTargets = @('Pause-Script','Confirm-Action')
$forbiddenChecks = @(
  @{ Parent='Menu-LimpezaDisco'; Key='1' },
  @{ Parent='Menu-LimpezaDisco'; Key='2' },
  @{ Parent='Menu-LimpezaDisco'; Key='3' },
  @{ Parent='Menu-Rede'; Key='1' },
  @{ Parent='Menu-Rede'; Key='5' }
)
foreach($c in $forbiddenChecks){
  $it = $flow | Where-Object { $_.Parent -eq $c.Parent -and $_.Key -eq $c.Key } | Select-Object -First 1
  if($null -eq $it){ continue }
  if($blockedTargets -contains (N $it.Function)){ throw "Forbidden helper target at $($c.Parent) key=$($c.Key): $($it.Function)" }
  if((N $it.Function) -eq 'TODO-Unresolved'){ throw "Unresolved target at $($c.Parent) key=$($c.Key)" }
}

$menuRoot = Join-Path $OutputRoot 'menu'
$root13Dir = Get-ChildItem -Path $menuRoot -Directory | Where-Object { $_.Name -like '*-Op-13-Diagnostico-de-Rede*' } | Select-Object -First 1
if($null -eq $root13Dir){ throw 'Missing expected root folder for option 13' }

$expectedDirs = @(
  '01-Op-1-Testar-Porta-TCP-Especifica',
  '02-Op-2-Ping-Sweep-Varredura-de-IPs-Ativos-na-Sub-rede',
  '03-Op-3-Scan-de-Faixa-de-Portas-TCP',
  '04-Op-4-Scan-de-Dispositivos-na-Rede-ARP-Scan',
  '05-Op-5-Descobrir-Nomes-de-Host-Hostnames-na-Rede',
  '06-Op-6-Consulta-WHOIS-DNS-de-um-Dominio',
  '07-Op-7-Scan-de-Servicos-Comuns-em-um-Host',
  '08-Op-8-Ver-Conexoes-de-Rede-Ativas-Netstat',
  '09-Op-9-Testar-Velocidade-da-Internet-Speedtest-cli',
  'Q-Voltar-ao-Menu-Principal'
)

$childNames = Get-ChildItem -Path $root13Dir.FullName -Directory | Select-Object -ExpandProperty Name
foreach($d in $expectedDirs){ if(-not ($childNames -contains $d)){ throw "Missing expected folder under Diagnostico de Rede: $d" } }

Write-Host 'VERIFY PASS'
