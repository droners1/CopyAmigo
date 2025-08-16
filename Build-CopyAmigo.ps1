# CopyAmigo EXE Builder Script
# This script converts CopyAmigo.ps1 to CopyAmigo.exe using PS2EXE

Write-Host "CopyAmigo EXE Builder v10.0" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Check if PS2EXE is installed
try {
    Import-Module ps2exe -ErrorAction Stop
    Write-Host "PS2EXE module found" -ForegroundColor Green
} catch {
    Write-Host "PS2EXE module not found. Installing..." -ForegroundColor Red
    Install-Module -Name ps2exe -Force -Scope CurrentUser
    Import-Module ps2exe
    Write-Host "PS2EXE module installed" -ForegroundColor Green
}

# Check if source script exists
if (-not (Test-Path "CopyAmigo.ps1")) {
    Write-Host "CopyAmigo.ps1 not found in current directory" -ForegroundColor Red
    Write-Host "Please run this script from the same directory as CopyAmigo.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "CopyAmigo.ps1 found" -ForegroundColor Green

# Build parameters
$sourceScript = "CopyAmigo.ps1"
$outputExe = "CopyAmigo.exe"

Write-Host "Building executable..." -ForegroundColor Yellow
Write-Host "   Source: $sourceScript" -ForegroundColor Gray
Write-Host "   Output: $outputExe" -ForegroundColor Gray

try {
    # PS2EXE conversion with security-optimized parameters
    # These parameters help reduce Windows Defender warnings
    ps2exe -inputFile $sourceScript -outputFile $outputExe `
        -noConsole `
        -noOutput `
        -noError `
        -credentialGUI `
        -title "CopyAmigo v10.0" `
        -description "Professional Survey Data Copy Tool" `
        -company "CopyAmigo Software" `
        -product "CopyAmigo Data Management Suite" `
        -copyright "Copyright 2024 CopyAmigo Software. All rights reserved." `
        -version "10.0.0.0" `
        -requireAdmin:$false `
        -supportOS `
        -longPaths `
        -winFormsDPIAware
    
    if (Test-Path $outputExe) {
        Write-Host "SUCCESS: CopyAmigo.exe created!" -ForegroundColor Green
        
        # Get file size
        $fileSize = [math]::Round((Get-Item $outputExe).Length / 1MB, 2)
        Write-Host "File size: $fileSize MB" -ForegroundColor Cyan
        
        # Get file info
        $fileInfo = Get-Item $outputExe
        Write-Host "Created: $($fileInfo.CreationTime)" -ForegroundColor Cyan
        Write-Host "Location: $($fileInfo.FullName)" -ForegroundColor Cyan
        
        Write-Host ""
        Write-Host "Build Complete!" -ForegroundColor Green
        Write-Host "You can now distribute CopyAmigo.exe as a standalone application." -ForegroundColor White
        Write-Host ""
        Write-Host "Distribution Notes:" -ForegroundColor Yellow
        Write-Host "- The .exe includes all PowerShell code and dependencies" -ForegroundColor Gray
        Write-Host "- No PowerShell installation required on target machines" -ForegroundColor Gray
        Write-Host "- Windows Defender may show a warning (click More info then Run anyway)" -ForegroundColor Gray
        Write-Host "- For enterprise deployment, consider code signing" -ForegroundColor Gray
        
    } else {
        Write-Host "FAILED: CopyAmigo.exe was not created" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "ERROR during conversion:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Ready to launch! Double-click CopyAmigo.exe to test." -ForegroundColor Cyan