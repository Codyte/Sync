# Flow Tree Generator - Sync Master

## Objective
`New-ScriptFlowTree.ps1` performs **static analysis** of `Sync_Master.ps1` and generates a navigable directory tree (`SyncMaster-Flow/`) representing menu flow, options, and function calls.

It does **not** execute the original Sync Master logic. It parses source code (AST) and emits structure + reports.

## Safety Notice
- Do not use the generator to execute `Sync_Master.ps1`.
- The source script must be treated as **analysis input only**.
- The generator must never invoke admin/dangerous operations from the source script.

## Run Generator
```powershell
pwsh -ExecutionPolicy Bypass -File .\New-ScriptFlowTree.ps1 \
  -SourcePath .\Sync_Master.ps1 \
  -OutputRoot .\SyncMaster-Flow \
  -Force \
  -GenerateReports \
  -EmitExtractedFunctions \
  -IncludeFunctionCalls \
  -DuplicateSharedNodes
```

## Run Verifier
```powershell
pwsh -ExecutionPolicy Bypass -File .\Verify-ScriptFlowTree.ps1 \
  -ReportJson .\SyncMaster-Flow\flow-report.json \
  -OutputRoot .\SyncMaster-Flow
```

## Generated Reports
- `SyncMaster-Flow/flow-report.md`: human summary of detected nodes/paths.
- `SyncMaster-Flow/flow-report.json`: structured data for automated validation.
- `SyncMaster-Flow/detected-menus.md`: detected menu switches + verified navigation paths.
- `SyncMaster-Flow/unresolved-functions.md`: unresolved targets/cases.
- `SyncMaster-Flow/manual-review.md`: manual follow-up points.
- `SyncMaster-Flow/_index/functions.json`: function index.
- `SyncMaster-Flow/_index/menu-map.json`: menu option mapping index.

## Validated Navigation Paths
- `__ROOT__ -> 2 -> Menu-Otimizacao -> 3 -> Menu-Desempenho`
- `__ROOT__ -> 13 -> Menu-DiagnosticoRede`

## Expected Remaining Items (`manual-review.md`)
These are expected and not part of current consolidation scope:
- unresolved `Q`/return branches
- inline switch blocks converted to TODO/wrapper
- variable-dispatched calls (e.g., `& $EntryPoint`) marked for manual verification
- dangerous command presence only flagged, never executed

## Scope Policy
- Do not modify `Sync_Master.ps1` during flow-tree consolidation.
- Do not attempt full closure of all `manual-review.md` findings in this phase.
