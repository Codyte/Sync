@echo off
rem Entrada dupla-clicavel e independente de pasta (%~dp0 = pasta deste .cmd).
rem Um .lnk NAO consegue referenciar a propria pasta, por isso este .cmd.
rem Prefere o powershell.exe do System32; se nao existir la, usa o do PATH.
rem O proprio script relanca no PowerShell 7 e pede UAC somente quando necessario.
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync_Master.ps1"
set "SYNCMASTER_EXIT=%ERRORLEVEL%"
if not "%SYNCMASTER_EXIT%"=="0" pause
exit /b %SYNCMASTER_EXIT%
