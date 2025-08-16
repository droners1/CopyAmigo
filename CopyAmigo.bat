@echo off
echo Starting CopyAmigo...
echo Current directory: %CD%
echo Script directory: %~dp0

REM Change to script directory
cd /d "%~dp0"
echo Changed to: %CD%

REM Check if PowerShell script exists
if not exist "CopyAmigo.ps1" (
    echo ERROR: PowerShell script 'CopyAmigo.ps1' not found in current directory
    echo Looking for: %CD%\CopyAmigo.ps1
    pause
    exit /b 1
)

echo PowerShell script found, launching...
powershell.exe -ExecutionPolicy Bypass -WindowStyle Normal -NoExit -Command "try { Write-Host 'PowerShell launched successfully' -ForegroundColor Green; Write-Host 'Script location:' (Get-Location); Write-Host 'Loading GUI...'; & './CopyAmigo.ps1' } catch { Write-Host 'ERROR:' $_.Exception.Message -ForegroundColor Red; Write-Host 'Script location:' (Get-Location); Write-Host 'Press Enter to exit...'; Read-Host }" 