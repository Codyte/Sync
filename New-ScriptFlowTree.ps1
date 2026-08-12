# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L75    Ensure-FlowShortcut
#   L97    Get-ChildrenByParent
#   L98    Show-MenuLoop
#   L121   ConvertTo-SafeLiteral
#   L122   Normalize-MenuTitle
#   L134   Get-ExpressionStringValue
#   L150   Get-CommandStringLiteralValue
#   L173   ConvertTo-Slug
#   L188   Format-OrderPrefix
#   L190   New-DirectorySafe
#   L191   Write-FileSafe
#   L209   Backup-OutputIfExists
#   L220   Get-AstParentFunctionName
#   L221   Test-MenuKey
#   L222   Get-SwitchClauseKeys
#   L237   Test-IsMenuSwitch
#   L246   Get-CommandCallsFromAst
#   L260   Get-FirstScriptFunctionCall
#   L261   Get-FunctionCallsFromAst
#   L262   Get-CaseCommands
#   L273   Get-MenuTargetFromClause
#   L281   New-ActionWrapperName
#   L288   Get-MenuTitlesForSwitch
#   L357   Write-NodeMetadata
#   L376   Write-Manifest
#   L389   Add-ReportItem
#   L391   Initialize-SourceIndex
#   L430   Write-Main
#   L457   Export-FunctionCallChildren
#   L472   Export-FunctionSubtree
#   L478   Export-MenuSwitchChildren
#   L532   Export-RootMenu
#   L591   Write-Reports
# ======================= END NAV INDEX =======================

# ====================== BEGIN NAV INDEX ======================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [switch]$DryRun,
    [switch]$Force,
    [int]$MaxDepth = 12,
    [switch]$IncludeFunctionCalls,
    [switch]$DuplicateSharedNodes,
    [switch]$GenerateReports,
    [switch]$EmitExtractedFunctions,
    [ValidateSet('utf8','unicode','ascii','utf7','utf32','bigendianunicode','default','oem')]
    [string]$Encoding = 'utf8'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FunctionMap = @{}
$script:MenuSwitchesByOwner = @{}
$script:Reports = New-Object System.Collections.Generic.List[object]
$script:SourceLines = @()
$script:SourceFullPath = $null
$script:Unresolved = New-Object System.Collections.Generic.List[object]
$script:DetectedMenus = New-Object System.Collections.Generic.List[object]
$script:ManualReview = New-Object System.Collections.Generic.List[string]
$script:IndexFunctions = New-Object System.Collections.Generic.List[object]
$script:IndexMenuMap = New-Object System.Collections.Generic.List[object]
$script:RootAst = $null
$script:HelperFunctions = @('Pause-Script','Confirm-Action','Registrar-Log','Write-Host','Write-Warning','Write-Error','Read-Host','Start-Sleep')

function Ensure-FlowShortcut {
    param([string]$Root)
    if ($DryRun) { return }
    $launcher = Join-Path $Root 'Start-SyncMasterFlow.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        $launcherContent = @'
[CmdletBinding()]
param(
    [switch]$NoRiskyActions = $true,
    [switch]$AllowRiskyActions,
    [switch]$AllowSensitiveActions,
    [string]$StartMenuFunction
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FlowJson = Join-Path $ScriptRoot 'flow-report.json'
$MenuRoot = Join-Path $ScriptRoot 'menu'
if (-not (Test-Path -LiteralPath $FlowJson -PathType Leaf)) { throw "flow-report.json not found: $FlowJson" }
if (-not (Test-Path -LiteralPath $MenuRoot -PathType Container)) { throw "menu directory not found: $MenuRoot" }
$Flow = Get-Content -Path $FlowJson | ConvertFrom-Json
Get-ChildItem -Path $MenuRoot -Filter 'main.ps1' -Recurse -File | ForEach-Object { . $_.FullName }
function Get-ChildrenByParent { param([string]$ParentName) @($Flow | Where-Object { $_.Parent -eq $ParentName } | Sort-Object @{Expression={ if($_.PSObject.Properties.Match('Order').Count -gt 0){[int]$_.Order}else{999999}}}, @{Expression={[string]$_.Key}}) }
function Show-MenuLoop { param([string]$ParentName,[string]$Caption) while($true){ $items=Get-ChildrenByParent -ParentName $ParentName; if(@($items).Count -eq 0){return}; Write-Host ""; Write-Host "=== $Caption ===" -ForegroundColor Cyan; foreach($i in $items){ Write-Host ("{0} - {1}" -f $i.Key,$i.Title)}; $choice=Read-Host 'Escolha uma opção'; if($choice -match '^[Qq]$'){return}; $node=@($items | Where-Object { [string]$_.Key -eq [string]$choice } | Select-Object -First 1); if(@($node).Count -eq 0){continue}; $child=Get-ChildrenByParent -ParentName ([string]$node[0].Function); if(@($child).Count -gt 0){ Show-MenuLoop -ParentName ([string]$node[0].Function) -Caption ([string]$node[0].Title)} else { $fn=[string]$node[0].Function; if(Get-Command -Name $fn -ErrorAction SilentlyContinue){ & $fn } else { Write-Warning "Function not loaded: $fn" } } } }
if($StartMenuFunction){ Show-MenuLoop -ParentName $StartMenuFunction -Caption $StartMenuFunction } else { Show-MenuLoop -ParentName '__ROOT__' -Caption 'SyncMaster Flow' }
'@
        Write-FileSafe -Path $launcher -Content $launcherContent -Overwrite:$true
    }
    $shortcutPath = Join-Path $Root 'Sync Master.lnk'
    $pwshPreferred = 'C:\Program Files\PowerShell\7\pwsh.exe'
    $pwsh = $pwshPreferred
    if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) {
        $pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
        if (-not $pwsh) { $pwsh = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
    $shortcut.WorkingDirectory = $Root
    $shortcut.WindowStyle = 1
    $shortcut.Description = "Executar Sync Master Flow"
    $shortcut.IconLocation = "$pwsh,0"
    $shortcut.Save()
}

function ConvertTo-SafeLiteral { param([AllowNull()][string]$Value) if ($null -eq $Value) { return "''" }; return "'" + ($Value -replace "'", "''") + "'" }
function Normalize-MenuTitle {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $t = $Text.Trim()
    $t = $t.Trim('"').Trim("'")
    $t = $t -replace '["'']\s*$',''
    $t = $t -replace '`"','"'
    $t = $t -replace "''","'"
    $t = $t -replace '\s+(Red|Green|Yellow|Cyan|Blue|Magenta|White|Gray|DarkGray|DarkRed|DarkGreen|DarkYellow|DarkBlue|DarkMagenta|DarkCyan|Black)\s*$',''
    $t = $t.Trim()
    return $t
}
function Get-ExpressionStringValue {
    param($AstNode)
    if ($null -eq $AstNode) { return $null }
    if ($AstNode -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $AstNode.Value }
    if ($AstNode -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { return $AstNode.Value }
    if ($AstNode -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        if ($AstNode.Value -is [string]) { return [string]$AstNode.Value }
        return $null
    }
    if ($AstNode -is [System.Management.Automation.Language.CommandExpressionAst]) { return Get-ExpressionStringValue -AstNode $AstNode.Expression }
    if ($AstNode -is [System.Management.Automation.Language.ParenExpressionAst]) { return Get-ExpressionStringValue -AstNode $AstNode.Pipeline }
    if ($AstNode -is [System.Management.Automation.Language.PipelineAst] -and $AstNode.PipelineElements.Count -eq 1) {
        return Get-ExpressionStringValue -AstNode $AstNode.PipelineElements[0]
    }
    return $null
}
function Get-CommandStringLiteralValue {
    param([System.Management.Automation.Language.CommandAst]$CommandAst)
    if ($null -eq $CommandAst) { return $null }
    $parts = @()
    $elements = @($CommandAst.CommandElements)
    $skipNextAsParamValue = $false
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $el = $elements[$i]
        if ($skipNextAsParamValue) { $skipNextAsParamValue = $false; continue }
        if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = [string]$el.ParameterName
            if ($pname -match '^(ForegroundColor|BackgroundColor|NoNewline|Separator)$') {
                $skipNextAsParamValue = $true
            }
            continue
        }
        $txt = Get-ExpressionStringValue -AstNode $el
        if ([string]::IsNullOrWhiteSpace($txt)) { continue }
        $parts += $txt
    }
    if (@($parts).Count -eq 0) { return $null }
    return (Normalize-MenuTitle ($parts -join ' '))
}
function ConvertTo-Slug {
    param([AllowNull()][string]$Text,[int]$MaxLength = 80)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 'Sem-Nome' }
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $ascii = $sb.ToString() -replace '[^a-zA-Z0-9\.]+','-' -replace '-+','-'
    $ascii = $ascii.Trim('-')
    if ([string]::IsNullOrWhiteSpace($ascii)) { $ascii = 'Sem-Nome' }
    if ($ascii.Length -gt $MaxLength) { $ascii = $ascii.Substring(0,$MaxLength).Trim('-') }
    return $ascii
}
function Format-OrderPrefix { param([int]$Order) return ('{0:00}' -f $Order) }

function New-DirectorySafe { param([string]$Path) if ($DryRun) { Write-Host "[DRY-RUN] mkdir $Path"; return }; if (-not (Test-Path $Path -PathType Container)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
function Write-FileSafe {
    param([string]$Path,[string]$Content,[switch]$Overwrite)
    if ($DryRun) { Write-Host "[DRY-RUN] write $Path"; return }
    if ((Test-Path $Path -PathType Leaf) -and -not $Overwrite) { return }
    $parent = Split-Path -Parent $Path
    if ($parent) { New-DirectorySafe -Path $parent }
    if ($Encoding -eq 'utf8') {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $enc = [System.Text.UTF8Encoding]::new($true)
        } else {
            $enc = New-Object System.Text.UTF8Encoding $true
        }
        [System.IO.File]::WriteAllText($Path, $Content, $enc)
    } else {
        Set-Content -Path $Path -Value $Content -Encoding $Encoding
    }
}

function Backup-OutputIfExists {
    if ($DryRun) { return }
    if (Test-Path $OutputRoot) {
        if (-not $Force) { throw "OutputRoot already exists. Use -Force to replace safely: $OutputRoot" }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$OutputRoot.backup.$stamp"
        Copy-Item -Path $OutputRoot -Destination $backup -Recurse -Force
        Remove-Item -Path $OutputRoot -Recurse -Force
    }
}

function Get-AstParentFunctionName { param($Ast) $c=$Ast; while($null -ne $c){ if($c -is [System.Management.Automation.Language.FunctionDefinitionAst]){return $c.Name}; $c=$c.Parent }; return $null }
function Test-MenuKey { param([AllowNull()][string]$Key) if([string]::IsNullOrWhiteSpace($Key)){return $false}; return ($Key -match '^(\d{1,3}(\.\d{1,3})?|00|ZZ|app|Q|q)$') }
function Get-SwitchClauseKeys {
    param($SwitchAst)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($clause in $SwitchAst.Clauses) {
        foreach ($expr in $clause.Item1) {
            $key = $null
            if ($expr -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $key = $expr.Value }
            elseif ($expr -is [System.Management.Automation.Language.ConstantExpressionAst]) { $key = [string]$expr.Value }
            else { $key = $expr.Extent.Text.Trim().Trim("'").Trim('"') }
            if ($key) { [void]$keys.Add($key) }
        }
    }
    return $keys
}

function Test-IsMenuSwitch {
    param($SwitchAst)
    $keys = Get-SwitchClauseKeys -SwitchAst $SwitchAst
    if (@($keys).Count -lt 2) { return $false }
    $valid = @($keys | Where-Object { Test-MenuKey $_ }).Count
    if ($valid -lt 2) { return $false }
    return $true
}

function Get-CommandCallsFromAst {
    param($Ast)
    $result = New-Object System.Collections.Generic.List[string]
    $commands = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($cmd in $commands) {
        $name = $cmd.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($name)) {
            $raw = $cmd.Extent.Text.Trim()
            if ($raw -match '^&\s*\$[A-Za-z_][A-Za-z0-9_]*') { $name = "DYNAMIC_CALL" }
        }
        if ($name) { [void]$result.Add($name) }
    }
    return $result
}
function Get-FirstScriptFunctionCall { param($Ast) foreach($name in (Get-CommandCallsFromAst $Ast)){ if($script:FunctionMap.ContainsKey($name)){return $name} }; return $null }
function Get-FunctionCallsFromAst { param($Ast) $calls=New-Object System.Collections.Generic.List[string]; foreach($n in (Get-CommandCallsFromAst $Ast)){ if($script:FunctionMap.ContainsKey($n) -and -not $calls.Contains($n)){ [void]$calls.Add($n) } }; return $calls }
function Get-CaseCommands {
    param($ClauseAst)
    $commands = @()
    $cmdAsts = @($ClauseAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach($c in $cmdAsts){
        $n = $c.GetCommandName()
        if([string]::IsNullOrWhiteSpace($n)){ $n = ($c.Extent.Text -split '\s+')[0] }
        if(-not [string]::IsNullOrWhiteSpace($n)){ $commands += $n }
    }
    return @($commands)
}
function Get-MenuTargetFromClause {
    param($ClauseAst)
    $calls = @(Get-FunctionCallsFromAst $ClauseAst)
    foreach($call in $calls){
        if($script:MenuSwitchesByOwner.ContainsKey($call)){ return $call }
    }
    return $null
}
function New-ActionWrapperName {
    param([string]$ParentName,[string]$Key)
    $p = ($ParentName -replace '[^A-Za-z0-9]','')
    $k = ($Key -replace '[^A-Za-z0-9]','_')
    return "Invoke-FlowAction-$p-Op-$k"
}

function Get-MenuTitlesForSwitch {
    param(
        [Parameter(Mandatory = $true)]$SwitchAst,
        [Parameter(Mandatory = $true)]$OwnerFunctionName
    )
    $map = @{}
    $keysInSwitch = @((Get-SwitchClauseKeys -SwitchAst $SwitchAst) | ForEach-Object { [string]$_ })

    # Scope strictly to owner function body and to local lines before this switch.
    $ownerAst = $null
    if ($OwnerFunctionName -and $script:FunctionMap.ContainsKey($OwnerFunctionName)) {
        $ownerAst = $script:FunctionMap[$OwnerFunctionName]
    }
    $startLine = 1
    if ($ownerAst) { $startLine = $ownerAst.Extent.StartLineNumber }
    $endLine = [Math]::Max($startLine, $SwitchAst.Extent.StartLineNumber - 1)
    $windowStart = [Math]::Max($startLine, $endLine - 140)

    $writeAsts = @()
    if ($ownerAst) {
        $writeAsts = $ownerAst.Body.FindAll({
            param($n)
            if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
            $name = $n.GetCommandName()
            return ($name -eq 'Write-Host' -or $name -eq 'Write-Warning')
        }, $true)
    } elseif ($OwnerFunctionName -eq '__ROOT__') {
        $globalStart = [Math]::Max(1, $windowStart)
        $globalEnd = $endLine
        for ($ln = $globalStart; $ln -le $globalEnd; $ln++) {
            if ($ln -le $script:SourceLines.Count) {
                $rawLine = $script:SourceLines[$ln - 1]
                $rawLine = Normalize-MenuTitle $rawLine
                if ($rawLine -match '^\s*Write-(Host|Warning)\b') {
                    # placeholder; handled by AST scan below
                }
            }
        }
        # fallback AST scan from root
        $writeAsts = $script:RootAst.FindAll({
            param($n)
            if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
            $name = $n.GetCommandName()
            if ($name -ne 'Write-Host' -and $name -ne 'Write-Warning') { return $false }
            return ($n.Extent.StartLineNumber -ge $windowStart -and $n.Extent.StartLineNumber -le $endLine)
        }, $true)
    }

    foreach ($cmd in $writeAsts) {
        $line = $cmd.Extent.StartLineNumber
        if ($line -lt $windowStart -or $line -gt $endLine) { continue }
        $raw = Get-CommandStringLiteralValue -CommandAst $cmd
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        if ($raw -match '^\s*[-=]{3,}') { continue }
        if ($raw -match '^\s*(?<key>(?:\d+(?:\.\d+)?|[A-Za-z]{1,3}))\s*(?:-|\.|\))\s+(?<title>.+?)\s*$') {
            $k = $Matches['key'].Trim()
            $t = Normalize-MenuTitle $Matches['title']
            if (($keysInSwitch -contains $k) -and -not $map.ContainsKey($k)) {
                $map[$k] = $t
            }
        }
    }

    foreach($k in $keysInSwitch){
      if(-not $map.ContainsKey($k)){ if($k -match '^[Qq]$'){ $map[$k]='Voltar' } else { $map[$k]="Opcao $k" } }
    }
    return $map
}

function Write-NodeMetadata {
    param([string]$Folder,[string]$Key,[string]$Title,[string]$Type,[string]$FunctionName,[int]$Order,[string]$Parent,[int]$SourceLine,[bool]$ReviewNeeded)
    $rootBase = if (Test-Path $OutputRoot) { (Resolve-Path $OutputRoot).Path } else { [System.IO.Path]::GetFullPath($OutputRoot) }
    $targetPath = $Folder.Replace($rootBase,'').TrimStart('\','/') -replace '\\','/'
    $content = @"
@{
    Key          = $(ConvertTo-SafeLiteral $Key)
    Title        = $(ConvertTo-SafeLiteral $Title)
    Type         = $(ConvertTo-SafeLiteral $Type)
    Function     = $(ConvertTo-SafeLiteral $FunctionName)
    Order        = $Order
    Parent       = $(ConvertTo-SafeLiteral $Parent)
    SourceLine   = $SourceLine
    TargetPath   = $(ConvertTo-SafeLiteral $targetPath)
    ReviewNeeded = `$$ReviewNeeded
}
"@
    Write-FileSafe -Path (Join-Path $Folder 'node.psd1') -Content $content -Overwrite:$Force
}
function Write-Manifest { param([string]$Folder,[string]$Key,[string]$Title,[string]$FunctionName,[int]$Order)
$content=@"
@{
    Id            = $(ConvertTo-SafeLiteral $Key)
    Titulo        = $(ConvertTo-SafeLiteral $Title)
    EntryPoint    = $(ConvertTo-SafeLiteral $FunctionName)
    Order         = $Order
    Visible       = `$true
    RequiresAdmin = `$false
}
"@
Write-FileSafe -Path (Join-Path $Folder 'manifest.psd1') -Content $content -Overwrite:$Force }

function Add-ReportItem { param([object]$obj) [void]$script:Reports.Add($obj) }

function Initialize-SourceIndex {
    param([string]$Path)
    $resolved = Resolve-Path $Path; $script:SourceFullPath = $resolved.Path; $script:SourceLines = Get-Content -Path $script:SourceFullPath
    $tokens=$null; $errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($script:SourceFullPath,[ref]$tokens,[ref]$errors)
    $script:RootAst = $ast
    if($errors -and @($errors).Count -gt 0){ foreach($e in @($errors)){ [void]$script:ManualReview.Add("Parse warning line $($e.Extent.StartLineNumber): $($e.Message)") } }
    $sources=@([pscustomobject]@{Path=$script:SourceFullPath;Ast=$ast})
    $moduleDirectory=Join-Path (Split-Path $script:SourceFullPath -Parent) 'modules'
    if(Test-Path -LiteralPath $moduleDirectory -PathType Container){
      foreach($moduleFile in Get-ChildItem -LiteralPath $moduleDirectory -Filter '*.psm1' -File | Sort-Object Name){
        $moduleTokens=$null; $moduleErrors=$null
        $moduleAst=[System.Management.Automation.Language.Parser]::ParseFile($moduleFile.FullName,[ref]$moduleTokens,[ref]$moduleErrors)
        if($moduleErrors -and @($moduleErrors).Count -gt 0){
          foreach($e in @($moduleErrors)){ [void]$script:ManualReview.Add("Parse warning $($moduleFile.Name):$($e.Extent.StartLineNumber): $($e.Message)") }
        }
        $sources += [pscustomobject]@{Path=$moduleFile.FullName;Ast=$moduleAst}
      }
    }
    foreach($source in $sources){
      $functions=$source.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)
      foreach($fn in $functions){
        if(-not $script:FunctionMap.ContainsKey($fn.Name)){
          $script:FunctionMap[$fn.Name]=$fn
          [void]$script:IndexFunctions.Add([pscustomobject]@{name=$fn.Name;source=$source.Path;start_line=$fn.Extent.StartLineNumber;end_line=$fn.Extent.EndLineNumber})
        }
      }
      $switches=$source.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst]},$true)
      foreach($sw in $switches){
        if(-not (Test-IsMenuSwitch $sw)){continue}
        $owner=Get-AstParentFunctionName $sw; if([string]::IsNullOrWhiteSpace($owner)){$owner='__ROOT__'}
        if(-not $script:MenuSwitchesByOwner.ContainsKey($owner)){ $script:MenuSwitchesByOwner[$owner]=New-Object System.Collections.Generic.List[object]}
        [void]$script:MenuSwitchesByOwner[$owner].Add($sw)
        [void]$script:DetectedMenus.Add([pscustomobject]@{owner=$owner;source=$source.Path;line=$sw.Extent.StartLineNumber;keys=(Get-SwitchClauseKeys $sw)})
      }
    }
    return $ast
}

function Write-Main {
    param([string]$Folder,[string]$Fn,[object]$FnAst,[object]$Clause,[string]$Parent,[string]$Key,[string]$Title)
    $path=Join-Path $Folder 'main.ps1'
    if($EmitExtractedFunctions -and $FnAst){ Write-FileSafe -Path $path -Content ($FnAst.Extent.Text + [Environment]::NewLine) -Overwrite:$Force; return $Fn }
    if($Clause -and $Fn -and $Fn -like 'Invoke-FlowAction-*'){
      $body = $Clause.Item2.Extent.Text.Trim()
      if($body.StartsWith('{') -and $body.EndsWith('}')){
        $body = $body.Substring(1, $body.Length - 2).Trim()
      }
      $wrapper = @"
function $Fn {
$body
}
"@
      Write-FileSafe -Path $path -Content ($wrapper + [Environment]::NewLine) -Overwrite:$Force
      return $Fn
    }
    if($Fn){ Write-FileSafe -Path $path -Content ("function Invoke-Node {`n    & '$Fn'`n}`n") -Overwrite:$Force; return $Fn }
    if($Clause){
      $body = $Clause.Item2.Extent.Text.Trim();
      Write-FileSafe -Path $path -Content ("# TODO unresolved branch from $Parent key $Key ($Title)`n" + $body + "`n") -Overwrite:$Force
      return 'TODO-Unresolved'
    }
    Write-FileSafe -Path $path -Content "# TODO unresolved`n" -Overwrite:$Force
    return 'TODO-Unresolved'
}

function Export-FunctionCallChildren {
 param($FunctionAst,[string]$ParentFolder,[string]$ParentName,[int]$Depth,[hashtable]$Visited)
 if(-not $IncludeFunctionCalls){ return }
 if($Depth -gt $MaxDepth){ return }
 if($script:MenuSwitchesByOwner.ContainsKey($ParentName)){ return }
 $calls=@(Get-FunctionCallsFromAst $FunctionAst) | Select-Object -Unique
 $order=0
 foreach($call in $calls){ if($call -eq $ParentName){continue}; if(-not $script:FunctionMap.ContainsKey($call)){continue}; if((-not $DuplicateSharedNodes) -and $Visited.ContainsKey($call)){continue}
  $order++; $folder=Join-Path $ParentFolder ((Format-OrderPrefix $order)+'-'+(ConvertTo-Slug $call))
  New-DirectorySafe $folder
  $fnAst=$script:FunctionMap[$call]; [void](Write-Main -Folder $folder -Fn $call -FnAst $fnAst -Clause $null -Parent $ParentName -Key ([string]$order) -Title $call)
  Write-NodeMetadata -Folder $folder -Key ([string]$order) -Title $call -Type 'FunctionCall' -FunctionName $call -Order $order -Parent $ParentName -SourceLine $fnAst.Extent.StartLineNumber -ReviewNeeded:$false
 }
}

function Export-FunctionSubtree { param([string]$FunctionName,[string]$Folder,[int]$Depth,[hashtable]$Visited)
 if($Depth -gt $MaxDepth){return}
 if(-not $script:MenuSwitchesByOwner.ContainsKey($FunctionName)){return}
 foreach($sw in $script:MenuSwitchesByOwner[$FunctionName]){ Export-MenuSwitchChildren -SwitchAst $sw -ParentFolder $Folder -ParentName $FunctionName -Depth $Depth -Visited $Visited }
}

function Export-MenuSwitchChildren {
 param([object]$SwitchAst,[string]$ParentFolder,[string]$ParentName,[int]$Depth,[hashtable]$Visited)
 if($Depth -gt $MaxDepth){return}
 $titleMap=Get-MenuTitlesForSwitch -SwitchAst $SwitchAst -OwnerFunctionName $ParentName
 $order=0
 foreach($clause in $SwitchAst.Clauses){
  foreach($expr in $clause.Item1){
   $key=$expr.Extent.Text.Trim().Trim("'").Trim('"')
   if(-not (Test-MenuKey $key)){continue}
   $order++
   $usedFallbackTitle = $false
   if ($titleMap.ContainsKey($key)) { $title = $titleMap[$key] } else { $title = "Opcao $key"; $usedFallbackTitle = $true }
   $title = Normalize-MenuTitle $title
   $menuTarget=Get-MenuTargetFromClause $clause.Item2
   $target = $menuTarget
   $prefix=if($key -match '^[Qq]$'){'Q'}elseif($key -eq 'ZZ'){'ZZ'}elseif($key -eq 'app'){'APP'}else{Format-OrderPrefix $order}
   $folderName = if($prefix -eq 'Q'){ 'Q-' + (ConvertTo-Slug $title) } else { "$prefix-Op-$key-" + (ConvertTo-Slug $title) }
   $folder=Join-Path $ParentFolder $folderName
   New-DirectorySafe $folder

   $caseText = $clause.Item2.Extent.Text.Trim()
   $isReturnOnly = ($caseText -match '^\s*(return|break|exit)\s*;?\s*$')
   $wrapperName = $null
   if(-not $target -and -not $isReturnOnly){ $wrapperName = New-ActionWrapperName -ParentName $ParentName -Key $key; $target = $wrapperName }
   $fnAst=$null; if($target -and $script:FunctionMap.ContainsKey($target)){$fnAst=$script:FunctionMap[$target]}
   $resolved=Write-Main -Folder $folder -Fn $target -FnAst $fnAst -Clause $clause -Parent $ParentName -Key $key -Title $title
   $type='Action'; if($menuTarget){$type='Menu'}; if($key -match '^[Qq]$' -or $isReturnOnly){$type='Return'}
   $review = ($resolved -eq 'TODO-Unresolved' -or $usedFallbackTitle)
   if($review){ [void]$script:Unresolved.Add([pscustomobject]@{parent=$ParentName;key=$key;title=$title;line=$expr.Extent.StartLineNumber}) }
   Write-NodeMetadata -Folder $folder -Key $key -Title $title -Type $type -FunctionName $resolved -Order $order -Parent $ParentName -SourceLine $expr.Extent.StartLineNumber -ReviewNeeded:$review
   if($ParentName -eq '__ROOT__'){ Write-Manifest -Folder $folder -Key $key -Title $title -FunctionName $resolved -Order $order }
   [void]$script:IndexMenuMap.Add([pscustomobject]@{menu_parent=$ParentName;option=$key;title=$title;function=$resolved;path=$folder})
   $origKind = 'Unknown'
   if($wrapperName){ $origKind = 'InlineCaseAction' }
   elseif($menuTarget){ $origKind = 'MenuFunction' }
   elseif($isReturnOnly){ $origKind = 'ReturnOnly' }
   Add-ReportItem ([pscustomobject]@{
      Path=$folder;Key=$key;Title=$title;Type=$type;Function=$resolved;Parent=$ParentName;SourceLine=$expr.Extent.StartLineNumber;
      Calls=@(if($fnAst){Get-FunctionCallsFromAst $fnAst}else{Get-FunctionCallsFromAst $clause.Item2});
      OriginalCaseCommands=@(Get-CaseCommands $clause.Item2);
      OriginalTargetKind=$origKind
   })

   if($target -and $script:MenuSwitchesByOwner.ContainsKey($target)){
    $newVisited=@{} + $Visited
    if($newVisited.ContainsKey($target)){ [void]$script:ManualReview.Add("Loop avoided at function $target") }
    else { $newVisited[$target]=$true; Export-FunctionSubtree -FunctionName $target -Folder $folder -Depth ($Depth+1) -Visited $newVisited }
   } elseif($fnAst) {
    Export-FunctionCallChildren -FunctionAst $fnAst -ParentFolder $folder -ParentName $target -Depth ($Depth+1) -Visited $Visited
   }
  }
 }
}

function Export-RootMenu {
 param([string]$MenuRoot)
 New-DirectorySafe $MenuRoot
 if(-not $script:MenuSwitchesByOwner.ContainsKey('__ROOT__')){
  $menuModule = Join-Path (Split-Path $script:SourceFullPath -Parent) 'modules\Menu.psm1'
  if(-not (Test-Path -LiteralPath $menuModule -PathType Leaf)){ throw 'No root menu switch or modules\Menu.psm1 detected.' }
  $tokens=$null; $errors=$null
  $menuAst=[System.Management.Automation.Language.Parser]::ParseFile($menuModule,[ref]$tokens,[ref]$errors)
  if($errors -and @($errors).Count -gt 0){ throw 'Failed to parse the data-driven menu module.' }
  $menuFunction=$menuAst.FindAll({
   param($n)
   $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-MenuPrincipal'
  },$true) | Select-Object -First 1
  if(-not $menuFunction){ throw 'Get-MenuPrincipal was not found in modules\Menu.psm1.' }

  $entries=@()
  foreach($table in $menuFunction.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] },$true)){
   $values=@{}
   foreach($pair in $table.KeyValuePairs){
    $name=Get-ExpressionStringValue -AstNode $pair.Item1
    $value=Get-ExpressionStringValue -AstNode $pair.Item2
    if($name){ $values[$name]=$value }
   }
   if($values.Id -and $values.Texto -and $values.Comando){
    $entries += [pscustomobject]@{Key=$values.Id;Title=$values.Texto;Function=$values.Comando;SourceLine=$table.Extent.StartLineNumber}
   }
  }
  if($entries.Count -eq 0){ throw 'Get-MenuPrincipal has no static menu entries.' }

  $order=0
  foreach($entry in $entries){
   $order++
   $key=[string]$entry.Key; $title=Normalize-MenuTitle ([string]$entry.Title); $target=[string]$entry.Function
   $isReturn=($target -eq '__SAIR__')
   $resolved=if($isReturn){'__SAIR__'}else{$target}
   $prefix=if($key -match '^[Qq]$'){'Q'}elseif($key -eq 'APP'){'APP'}else{Format-OrderPrefix $order}
   $folderName=if($prefix -eq 'Q'){ 'Q-' + (ConvertTo-Slug $title) }else{ "$prefix-Op-$key-" + (ConvertTo-Slug $title) }
   $folder=Join-Path $MenuRoot $folderName
   New-DirectorySafe $folder
   $fnAst=$null; if($script:FunctionMap.ContainsKey($target)){$fnAst=$script:FunctionMap[$target]}
   if($isReturn){ Write-FileSafe -Path (Join-Path $folder 'main.ps1') -Content "# Return from the data-driven root menu.`n" -Overwrite:$Force }
   else { [void](Write-Main -Folder $folder -Fn $target -FnAst $fnAst -Clause $null -Parent '__ROOT__' -Key $key -Title $title) }
   $type=if($isReturn){'Return'}elseif($fnAst -and $script:MenuSwitchesByOwner.ContainsKey($target)){'Menu'}else{'Action'}
   Write-NodeMetadata -Folder $folder -Key $key -Title $title -Type $type -FunctionName $resolved -Order $order -Parent '__ROOT__' -SourceLine $entry.SourceLine -ReviewNeeded:$false
   Write-Manifest -Folder $folder -Key $key -Title $title -FunctionName $resolved -Order $order
   [void]$script:IndexMenuMap.Add([pscustomobject]@{menu_parent='__ROOT__';option=$key;title=$title;function=$resolved;path=$folder})
   Add-ReportItem ([pscustomobject]@{Path=$folder;Key=$key;Title=$title;Type=$type;Function=$resolved;Parent='__ROOT__';SourceLine=$entry.SourceLine;Calls=@();OriginalCaseCommands=@();OriginalTargetKind='DataDrivenMenuEntry'})
   if($fnAst -and $script:MenuSwitchesByOwner.ContainsKey($target)){
    $visited=@{'__ROOT__'=$true}; $visited[$target]=$true
    Export-FunctionSubtree -FunctionName $target -Folder $folder -Depth 2 -Visited $visited
   }
  }
  return
 }
 $root=$null; $best=-1
 foreach($sw in $script:MenuSwitchesByOwner['__ROOT__']){ $count=@(Get-SwitchClauseKeys $sw).Count; if($count -gt $best){$best=$count; $root=$sw} }
 Export-MenuSwitchChildren -SwitchAst $root -ParentFolder $MenuRoot -ParentName '__ROOT__' -Depth 1 -Visited @{'__ROOT__'=$true}
}

function Write-Reports {
 param([string]$Root)
 $flowJson=Join-Path $Root 'flow-report.json'; $flowMd=Join-Path $Root 'flow-report.md'; $unres=Join-Path $Root 'unresolved-functions.md'; $menus=Join-Path $Root 'detected-menus.md'; $manual=Join-Path $Root 'manual-review.md'
 $idx=Join-Path $Root '_index'; New-DirectorySafe $idx
 if(-not $DryRun){ $script:Reports | ConvertTo-Json -Depth 8 | Set-Content -Path $flowJson -Encoding $Encoding }
 $md=@(); $md += '# flow-report'; $md += "- Source: $($script:SourceFullPath)"; $md += "- Functions: $($script:FunctionMap.Count)"; $md += "- Menus: $($script:DetectedMenus.Count)"; $md += "- Options: $($script:Reports.Count)"; $md += "- Unresolved: $($script:Unresolved.Count)"; $md += ''; $md += '## Tree summary'; foreach($r in $script:Reports){ $md += "- [$($r.Type)] $($r.Key) $($r.Title) -> $($r.Function)" }
 Write-FileSafe -Path $flowMd -Content ($md -join "`r`n") -Overwrite:$true

 $u=@('# unresolved-functions'); foreach($x in $script:Unresolved){ $u += "- Parent=$($x.parent) Key=$($x.key) Title=$($x.title) Line=$($x.line)" }; Write-FileSafe -Path $unres -Content ($u -join "`r`n") -Overwrite:$true
 $m=@('# detected-menus'); foreach($d in $script:DetectedMenus){ $m += "- Owner=$($d.owner) Line=$($d.line) Keys=$([string]::Join(',', $d.keys))" }
 $m += ''
 $m += '## Verified navigation paths'
 $root2 = $script:Reports | Where-Object { $_.Parent -eq '__ROOT__' -and $_.Key -eq '2' } | Select-Object -First 1
 if ($root2) { $m += "- __ROOT__ -> 2 -> $($root2.Function)" }
 $root13 = $script:Reports | Where-Object { $_.Parent -eq '__ROOT__' -and $_.Key -eq '13' } | Select-Object -First 1
 if ($root13) { $m += "- __ROOT__ -> 13 -> $($root13.Function)" }
 $mOpt3 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-Otimizacao' -and $_.Key -eq '3' } | Select-Object -First 1
 if ($mOpt3) { $m += "- Menu-Otimizacao -> 3 -> $($mOpt3.Function)" }
 $nr1 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '1' } | Select-Object -First 1
 $nr2 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '2' } | Select-Object -First 1
 $nr3 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '3' } | Select-Object -First 1
 $nr4 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '4' } | Select-Object -First 1
 $nr5 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '5' } | Select-Object -First 1
 $nr6 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '6' } | Select-Object -First 1
 $nr7 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '7' } | Select-Object -First 1
 $nr8 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '8' } | Select-Object -First 1
 $nr9 = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and $_.Key -eq '9' } | Select-Object -First 1
 $nrQ = $script:Reports | Where-Object { $_.Parent -eq 'Menu-DiagnosticoRede' -and ($_.Key -eq 'Q' -or $_.Key -eq 'q') } | Select-Object -First 1
 if ($nr1) { $m += "- Menu-DiagnosticoRede -> 1 -> $($nr1.Function)" }
 if ($nr2) { $m += "- Menu-DiagnosticoRede -> 2 -> $($nr2.Function)" }
 if ($nr3) { $m += "- Menu-DiagnosticoRede -> 3 -> $($nr3.Function)" }
 if ($nr4) { $m += "- Menu-DiagnosticoRede -> 4 -> $($nr4.Function)" }
 if ($nr5) { $m += "- Menu-DiagnosticoRede -> 5 -> $($nr5.Function)" }
 if ($nr6) { $m += "- Menu-DiagnosticoRede -> 6 -> $($nr6.Function)" }
 if ($nr7) { $m += "- Menu-DiagnosticoRede -> 7 -> $($nr7.Function)" }
 if ($nr8) { $m += "- Menu-DiagnosticoRede -> 8 -> $($nr8.Function)" }
 if ($nr9) { $m += "- Menu-DiagnosticoRede -> 9 -> $($nr9.Function)" }
 if ($nrQ) { $m += "- Menu-DiagnosticoRede -> Q -> Voltar ao Menu Principal" }
 Write-FileSafe -Path $menus -Content ($m -join "`r`n") -Overwrite:$true
 $mr=@('# manual-review');
 $mr += '- opções sem destino identificado'; foreach($x in $script:Unresolved){ $mr += "  - $($x.parent)::$($x.key)" }
 $mr += '- chamadas por variável (& $EntryPoint etc.) podem precisar revisão manual'
 $mr += '- blocos inline no switch viram TODO/wrapper'
 $mr += '- comandos potencialmente perigosos do script-fonte não foram executados; revisão humana recomendada'
 foreach($i in $script:ManualReview){ $mr += "- $i" }
 Write-FileSafe -Path $manual -Content ($mr -join "`r`n") -Overwrite:$true

 if(-not $DryRun){ $script:IndexFunctions | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $idx 'functions.json') -Encoding $Encoding; $script:IndexMenuMap | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $idx 'menu-map.json') -Encoding $Encoding }
}

try {
 Backup-OutputIfExists
 New-DirectorySafe $OutputRoot
 Initialize-SourceIndex -Path $SourcePath | Out-Null
 Export-RootMenu -MenuRoot (Join-Path $OutputRoot 'menu')
 if($GenerateReports){ Write-Reports -Root $OutputRoot }
 Ensure-FlowShortcut -Root $OutputRoot
 Write-Host "Done. Functions=$($script:FunctionMap.Count) Nodes=$($script:Reports.Count) Output=$OutputRoot"
} catch {
    Write-Error ("{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
    exit 1
}
