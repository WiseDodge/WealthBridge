@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0normalize-fidelity-snapshots.ps1" -AggregateSameSymbolRows
echo.
pause
