# CopyAmigo - Clean PowerShell GUI for Project Data Copy
# Following PowerShell best practices for reliability and simplicity

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptVersion = "v10.0 - Professional Edition"

# Get current directory and project info
$currentDir = $PWD.Path
$projectFolderName = Split-Path $currentDir -Leaf
$sourceDir = $currentDir

# Global variables
$script:projectFolderName = $projectFolderName
$script:sourceDir = $sourceDir
$script:destinationDir = ""
$script:selectedSubfolders = @()
$script:cancelRequested = $false
$script:activeProcesses = @()
# Determine default Projects root (prefer H:, else C:\Projects, else prompt once)
# Check if H: drive is actually accessible for operations, not just if path exists
$hDriveAccessible = $false
if (Test-Path 'H:\Survey\LIDAR PHOTOGRAMMETRY PROJECTS') {
    try {
        # Test if we can actually write to the H: drive by attempting to create a test file
        $testFile = 'H:\Survey\LIDAR PHOTOGRAMMETRY PROJECTS\CopyAmigo_Test_Access.tmp'
        $null = New-Item -ItemType File -Path $testFile -Force -ErrorAction Stop
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        $hDriveAccessible = $true
    } catch {
        $hDriveAccessible = $false
        # Removed Write-Host to prevent popups in executable
    }
}

if ($hDriveAccessible) {
    $script:projectsRoot = 'H:\Survey\LIDAR PHOTOGRAMMETRY PROJECTS'
    # Removed Write-Host to prevent popups in executable
} elseif (Test-Path 'C:\Projects') {
    $script:projectsRoot = 'C:\Projects'
    # Removed Write-Host to prevent popups in executable
} else {
    try {
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.Description = 'Select the Projects root folder'
        if ($fb.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $fb.SelectedPath) {
            $script:projectsRoot = $fb.SelectedPath
            # Removed Write-Host to prevent popups in executable
        } else {
            $script:projectsRoot = 'C:\Projects'
            # Removed Write-Host to prevent popups in executable
        }
    } finally { if ($fb) { $fb.Dispose() } }
}

# IMPORTANT: Always use C:\Projects for destinations, regardless of source projects root
$script:destinationRoot = 'C:\Projects'
# Removed Write-Host to prevent popups in executable

# OPTIMIZATION VARIABLES
$script:sourceDriveType = ""
$script:destDriveType = ""
$script:optimalThreads = 32
$script:optimalParams = ""
$script:parallelJobs = @()
$script:copyStats = @{
    TotalFiles = 0
    CopiedFiles = 0
    TotalSize = 0
    CopiedSize = 0
    StartTime = $null
    CurrentFile = ""
    Speed = 0
}

# Clean logging variables
$script:lastLoggedPercent = -1
$script:lastLoggedFile = ""
$script:totalOperationFiles = 0
$script:totalOperationSize = 0

# WINDOWS EXPLORER PROGRESS DIALOG VARIABLES
$script:progressDialog = $null
$script:progressDialogActive = $false
$script:useWindowsProgressDialog = $true  # Default to using Windows Explorer-style progress

# WINDOWS EXPLORER PROGRESS DIALOG FUNCTIONS
function Initialize-WindowsProgressDialog {
    param([string]$title = "Copying Files", [string]$description = "Preparing to copy files...")
    
    try {
        # Create the Windows Explorer progress dialog COM object
        $script:progressDialog = New-Object -ComObject "Shell.Application"
        $script:progressDialogActive = $true
        
        Write-Status "PROGRESS: Windows Explorer progress dialog initialized"
        Write-Status "PROGRESS: Title: $title"
        Write-Status "PROGRESS: Description: $description"
        
        return $true
    } catch {
        Write-Status "PROGRESS: Failed to initialize Windows progress dialog: $($_.Exception.Message)"
        Write-Status "PROGRESS: Falling back to built-in progress bar"
        return $false
    }
}

function Show-WindowsProgressDialog {
    param(
        [string]$title = "CopyAmigo - Professional Copy",
        [string]$operation = "Copying project files...",
        [string]$sourceDescription = "",
        [string]$destinationDescription = "",
        [int]$totalFiles = 0,
        [long]$totalSize = 0
    )
    
    try {
        # Use robocopy with built-in progress display for Windows Explorer-like experience
        Write-Status "PROGRESS: Showing Windows Explorer-style progress for copy operation"
        Write-Status "PROGRESS: Operation: $operation"
        Write-Status "PROGRESS: Source: $sourceDescription"
        Write-Status "PROGRESS: Destination: $destinationDescription"
        Write-Status "PROGRESS: Files: $totalFiles, Size: $([math]::Round($totalSize / 1MB, 2)) MB"
        
        # Store progress info for status updates
        $script:copyStats.TotalFiles = $totalFiles
        $script:copyStats.TotalSize = $totalSize
        $script:copyStats.CurrentFile = $operation
        $script:copyStats.StartTime = Get-Date
        
        return $true
    } catch {
        Write-Status "PROGRESS: Error showing Windows progress dialog: $($_.Exception.Message)"
        return $false
    }
}

function Update-WindowsProgressDialog {
    param(
        [string]$currentFile = "",
        [int]$filesCompleted = 0,
        [long]$sizeCompleted = 0,
        [string]$statusMessage = ""
    )
    
    if ($script:progressDialogActive) {
        try {
            # Update copy statistics
            $script:copyStats.CopiedFiles = $filesCompleted
            $script:copyStats.CopiedSize = $sizeCompleted
            $script:copyStats.CurrentFile = $currentFile
            
            # Calculate progress percentage
            $fileProgress = if ($script:copyStats.TotalFiles -gt 0) { 
                [math]::Round(($filesCompleted / $script:copyStats.TotalFiles) * 100, 1) 
            } else { 0 }
            
            $sizeProgress = if ($script:copyStats.TotalSize -gt 0) { 
                [math]::Round(($sizeCompleted / $script:copyStats.TotalSize) * 100, 1) 
            } else { 0 }
            
            # Calculate speed and time remaining
            $elapsed = ((Get-Date) - $script:copyStats.StartTime).TotalSeconds
            $speed = if ($elapsed -gt 0) { $sizeCompleted / $elapsed } else { 0 }
            $script:copyStats.Speed = $speed
            
            # Update main progress bar
            $overallProgress = [math]::Max($fileProgress, $sizeProgress)
            Update-Progress $overallProgress
            
            # Don't update global progress here as it causes cumulative counting issues
            # Global progress is updated properly in Complete-Operation when each folder finishes
            
            # Create detailed status message
            $speedText = if ($speed -gt 1MB) { 
                "$([math]::Round($speed / 1MB, 1)) MB/s" 
            } elseif ($speed -gt 1KB) { 
                "$([math]::Round($speed / 1KB, 1)) KB/s" 
            } else { 
                "$([math]::Round($speed, 1)) B/s" 
            }
            
            $remainingSize = $script:copyStats.TotalSize - $sizeCompleted
            $timeRemaining = if ($speed -gt 0) { 
                $remainingSeconds = $remainingSize / $speed
                $minutes = [math]::Floor($remainingSeconds / 60)
                $seconds = [math]::Floor($remainingSeconds % 60)
                "${minutes}m ${seconds}s"
            } else { 
                "Calculating..." 
            }
            
            $detailedStatus = "PROGRESS: $overallProgress% complete - $speedText - $timeRemaining remaining"
            if ($currentFile) {
                $detailedStatus += " - Currently: $currentFile"
            }
            
            Write-Status $detailedStatus
            
        } catch {
            Write-Status "PROGRESS: Error updating Windows progress dialog: $($_.Exception.Message)"
        }
    }
}

function Close-WindowsProgressDialog {
    try {
        if ($script:progressDialogActive) {
            Write-Status "PROGRESS: Closing Windows Explorer progress dialog"
            $script:progressDialogActive = $false
            
            # Final statistics
            $elapsed = ((Get-Date) - $script:copyStats.StartTime).TotalSeconds
            $avgSpeed = if ($elapsed -gt 0) { $script:copyStats.CopiedSize / $elapsed } else { 0 }
            
            $speedText = if ($avgSpeed -gt 1MB) { 
                "$([math]::Round($avgSpeed / 1MB, 1)) MB/s" 
            } elseif ($avgSpeed -gt 1KB) { 
                "$([math]::Round($avgSpeed / 1KB, 1)) KB/s" 
            } else { 
                "$([math]::Round($avgSpeed, 1)) B/s" 
            }
            
            Write-Status "PROGRESS: Copy completed in $([math]::Round($elapsed, 1))s at average $speedText"
            Write-Status "PROGRESS: Total files: $($script:copyStats.CopiedFiles), Total size: $([math]::Round($script:copyStats.CopiedSize / 1MB, 2)) MB"
        }
        
        if ($script:progressDialog) {
            $script:progressDialog = $null
        }
        
    } catch {
        Write-Status "PROGRESS: Error closing Windows progress dialog: $($_.Exception.Message)"
    }
}

function Start-WindowsStyleCopy {
    param(
        [string]$sourcePath,
        [string]$destPath,
        [string]$folderName,
        [string]$operation = "Copying",
        [System.Windows.Forms.TextBox]$debugTextBox = $null
    )

    try {
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Checking if source path exists: $sourcePath" }
        if (-not (Test-Path $sourcePath)) {
            if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] ERROR: Source path does not exist!" }
            Write-CopyError -filePath $sourcePath -errorDescription "Source path does not exist" -action "aborted"
            return $false
        }

        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Starting detailed source analysis (Get-ChildItem -Recurse)..." }
        $analysisStart = Get-Date
        $sourceItems = Get-ChildItem $sourcePath -Recurse -ErrorAction SilentlyContinue
        $analysisTime = ((Get-Date) - $analysisStart).TotalSeconds
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Source analysis completed in $([math]::Round($analysisTime, 2)) seconds" }
        
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Filtering files and folders..." }
        $filterStart = Get-Date
        $sourceFiles = $sourceItems | Where-Object { -not $_.PSIsContainer }
        $sourceFolders = $sourceItems | Where-Object { $_.PSIsContainer }

        $totalFiles = $sourceFiles.Count
        $totalFolders = $sourceFolders.Count
        $totalSize = ($sourceFiles | Measure-Object -Property Length -Sum).Sum
        $filterTime = ((Get-Date) - $filterStart).TotalSeconds
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Filtering completed in $([math]::Round($filterTime, 2)) seconds - $totalFiles files, $([math]::Round($totalSize/1GB, 2)) GB" }

        # Log operation start with clean format
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Writing operation start log..." }
        Write-OperationStart -totalFiles $totalFiles -totalSize $totalSize -sourceDir $sourcePath -destDir $destPath -operation "$operation $folderName"

        # Show Windows-style progress
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Showing Windows progress dialog..." }
        Show-WindowsProgressDialog -title "CopyAmigo - Professional Copy" -operation "$operation $folderName" -sourceDescription $sourcePath -destinationDescription $destPath -totalFiles $totalFiles -totalSize $totalSize

        # Prepare robocopy command and output files
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Preparing robocopy command..." }
        
        # Use optimized parameters (no verbose logging unless in debug mode)
        if ($debugTextBox) {
            # In debug mode, add minimal verbose flags for monitoring
            $debugParams = $script:optimalParams -replace "/NP /NDL /NJH /NJS", "/NP"
            $debugParams += " /V"  # Only verbose, no timestamps/full paths for speed
        } else {
            # Production mode - use fully optimized parameters (no verbose logging)
            $debugParams = $script:optimalParams
        }
        $outputFile = [System.IO.Path]::GetTempFileName()
        $errorFile = [System.IO.Path]::GetTempFileName()

        # Build robocopy argument string with proper quoting for paths that contain spaces
        $robocopyArgs = "`"$sourcePath`" `"$destPath`" $debugParams"
        if ($debugTextBox) { 
            Add-DebugMessage $debugTextBox "    [COPY] Robocopy command: robocopy $robocopyArgs" 
            Add-DebugMessage $debugTextBox "    [COPY] Source exists: $(Test-Path $sourcePath)"
            Add-DebugMessage $debugTextBox "    [COPY] Dest parent exists: $(Test-Path (Split-Path $destPath -Parent))"
            Add-DebugMessage $debugTextBox "    [COPY] Output file: $outputFile"
            Add-DebugMessage $debugTextBox "    [COPY] Error file: $errorFile"
        }

        # Start robocopy directly with Start-Process, ensuring paths with spaces are handled correctly
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Starting robocopy process..." }
        $proc = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -WindowStyle Hidden -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile -PassThru
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Robocopy process started with PID: $($proc.Id)" }
        $startTime = Get-Date
        $lastLength = 0
        $lastErrorLength = 0
        $lastUserUpdate = Get-Date
        $sourceFileCount = 0
        $sourceTotalSize = 0
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] WARNING: Starting ANOTHER source analysis (this might be the bottleneck!)..." }
        $redundantAnalysisStart = Get-Date
        try {
            $sourceItems = Get-ChildItem $sourcePath -Recurse -ErrorAction SilentlyContinue
            $sourceFileCount = ($sourceItems | Where-Object { -not $_.PSIsContainer }).Count
            $sourceTotalSize = ($sourceItems | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
            $redundantAnalysisTime = ((Get-Date) - $redundantAnalysisStart).TotalSeconds
            if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Redundant analysis completed in $([math]::Round($redundantAnalysisTime, 2)) seconds" }
        } catch {
            $redundantAnalysisTime = ((Get-Date) - $redundantAnalysisStart).TotalSeconds
            if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Redundant analysis failed after $([math]::Round($redundantAnalysisTime, 2)) seconds" }
        }
        $lastFileName = ""
        $lastProgressLine = ""
        $loopCount = 0
        $lastOutputChange = Get-Date
        $lastOutputSize = 0
        $stuckThreshold = 300  # 5 minutes without output change = stuck
        
        # Loop: While robocopy is running, read output and update progress
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Entering monitoring loop..." }
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 500
            $loopCount++
            
            # Provide time-based progress estimate for global progress (less frequent updates)
            if (($loopCount % 20) -eq 0 -and $script:globalProgress.TotalSize -gt 0) {
                $elapsed = ((Get-Date) - $startTime).TotalSeconds
                
                # Only update if we have a reasonable time elapsed and haven't completed this operation yet
                if ($elapsed -gt 2) {
                    # Calculate current overall progress to see if we should update
                    $currentOverallProgress = if ($script:globalProgress.TotalSize -gt 0) {
                        ($script:globalProgress.CompletedSize / $script:globalProgress.TotalSize) * 100
                    } else { 0 }
                    
                    # Only update if progress change would be >= 5%
                    $estimatedProgress = [math]::Min($elapsed / ($elapsed + 20), 0.85)  # More conservative estimate
                    $estimatedOperationSize = [math]::Round($sourceTotalSize * $estimatedProgress)
                    $newOverallProgress = if ($script:globalProgress.TotalSize -gt 0) {
                        (($script:globalProgress.CompletedSize + $estimatedOperationSize) / $script:globalProgress.TotalSize) * 100
                    } else { 0 }
                    
                    # Only update if progress increased by at least 5%
                    if (($newOverallProgress - $currentOverallProgress) -ge 5) {
                        # Just update the current operation name for display - don't mess with the counts
                        $script:globalProgress.CurrentOperation = $folderName
                        Update-AccurateProgress
                    }
                }
            }
            
            # Debug every 10 iterations (5 seconds) with more detail
            if ($debugTextBox -and ($loopCount % 10) -eq 0) {
                $elapsed = ((Get-Date) - $startTime).TotalSeconds
                
                # Check if robocopy output file exists and has content
                $outputExists = Test-Path $outputFile
                $outputSize = if ($outputExists) { (Get-Item $outputFile).Length } else { 0 }
                $errorExists = Test-Path $errorFile
                $errorSize = if ($errorExists) { (Get-Item $errorFile).Length } else { 0 }
                
                # Check if output has changed (progress detection)
                if ($outputSize -ne $lastOutputSize) {
                    $lastOutputChange = Get-Date
                    $lastOutputSize = $outputSize
                }
                
                $timeSinceLastChange = ((Get-Date) - $lastOutputChange).TotalSeconds
                Add-DebugMessage $debugTextBox "    [COPY] Loop $loopCount (${elapsed}s) - Output: ${outputSize}bytes, Error: ${errorSize}bytes, Stuck: ${timeSinceLastChange}s"
                
                # Detect if robocopy appears stuck
                if ($timeSinceLastChange -gt $stuckThreshold) {
                    Add-DebugMessage $debugTextBox "    [COPY] WARNING: Robocopy appears stuck! No output change for $([math]::Round($timeSinceLastChange, 1)) seconds"
                    Add-DebugMessage $debugTextBox "    [COPY] Consider killing the process if this continues..."
                }
                
                # Show last few lines of robocopy output if available
                if ($outputExists -and $outputSize -gt 0) {
                    try {
                        $recentOutput = Get-Content $outputFile -Tail 3 -ErrorAction SilentlyContinue
                        if ($recentOutput) {
                            Add-DebugMessage $debugTextBox "    [COPY] Recent robocopy output:"
                            foreach ($line in $recentOutput) {
                                if ($line.Trim()) {
                                    Add-DebugMessage $debugTextBox "    [COPY]   > $($line.Trim())"
                                }
                            }
                        }
                    } catch {
                        Add-DebugMessage $debugTextBox "    [COPY] Could not read recent output: $($_.Exception.Message)"
                    }
                }
                
                # Check for errors
                if ($errorExists -and $errorSize -gt 0) {
                    try {
                        $errorContent = Get-Content $errorFile -Raw -ErrorAction SilentlyContinue
                        if ($errorContent -and $errorContent.Trim()) {
                            Add-DebugMessage $debugTextBox "    [COPY] ERROR OUTPUT: $($errorContent.Trim())"
                        }
                    } catch {
                        Add-DebugMessage $debugTextBox "    [COPY] Could not read error file: $($_.Exception.Message)"
                    }
                }
            }
            
            $currentFileName = ""
            if (Test-Path $outputFile) {
                $content = Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
                if ($null -ne $content) {
                    $currLen = $content.Length
                    if ($currLen -gt $lastLength) {
                        $newText = $content.Substring($lastLength)
                        
                        # Debug: Show what new content we got
                        if ($debugTextBox -and $newText.Trim()) {
                            $newLines = $newText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2
                            foreach ($line in $newLines) {
                                Add-DebugMessage $debugTextBox "    [COPY] NEW: $($line.Trim())"
                            }
                        }
                        $lines = $newText -split "`n"
                        foreach ($line in $lines) {
                            $trimmed = $line.Trim()
                            # Try to extract current file name from robocopy output
                            if ($trimmed -match "^\\\\?\\?(.+)$" -or $trimmed -match "^[A-Z]:\\.+$") {
                                $currentFileName = $trimmed
                            }
                        }
                        $lastLength = $currLen
                    }
                }
            }
            # Clean progress update every 2 seconds
            if (((Get-Date) - $lastUserUpdate).TotalSeconds -ge 2) {
                $destFileCount = 0
                $destTotalSize = 0
                try {
                    if (Test-Path $destPath) {
                        $destItems = Get-ChildItem $destPath -Recurse -ErrorAction SilentlyContinue
                        $destFileCount = ($destItems | Where-Object { -not $_.PSIsContainer }).Count
                        $destTotalSize = ($destItems | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
                    }
                } catch {}
                
                # Calculate progress based on size primarily
                $percent = 0
                if ($sourceTotalSize -gt 0) {
                    $percent = [math]::Round(($destTotalSize / $sourceTotalSize) * 100)
                    
                    # For large files where size jumps to 100% immediately, use time-based estimate
                    if ($percent -ge 100 -and $proc -and !$proc.HasExited) {
                        $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
                        # Estimate based on typical network speeds (conservative 30 MB/s)
                        $estimatedTotalTime = $sourceTotalSize / (30 * 1MB)
                        $timePercent = [math]::Round(($elapsedSeconds / $estimatedTotalTime) * 100)
                        $percent = [math]::Min($timePercent, 95)  # Cap at 95% until actually done
                    }
                } elseif ($sourceFileCount -gt 0) {
                    $percent = [math]::Round(($destFileCount / $sourceFileCount) * 100)
                }
                
                # Cap at 100%
                if ($percent -gt 100) {
                    $percent = 100
                }
                
                # Use clean progress logging - only if we have meaningful progress
                if ($percent -gt 0 -and $percent -le 100) {
                    if ($currentFileName) {
                        # Try to get file size if available
                        $fileSize = 0
                        try {
                            if (Test-Path $currentFileName) {
                                $fileSize = (Get-Item $currentFileName).Length
                            }
                        } catch {}
                        
                        Write-CleanProgress -currentFile (Split-Path $currentFileName -Leaf) -fileSize $fileSize -percent $percent
                    } else {
                        # If no current file name, show generic progress
                        Write-CleanProgress -currentFile "Processing..." -fileSize 0 -percent $percent
                    }
                }
                
                $lastUserUpdate = Get-Date
            }
            [System.Windows.Forms.Application]::DoEvents()
        }
        # Wait for robocopy to fully exit
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Exited monitoring loop, waiting for process to fully exit..." }
        $proc.WaitForExit()
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Process fully exited" }
        $exitCode = $proc.ExitCode
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "    [COPY] Exit code: $exitCode" }
        # After robocopy is done, output clean summary
        Write-CleanSummary -totalFiles $destFileCount -totalSize $destTotalSize -operation "Copy complete"

        # After robocopy is done, output remaining content
        if (Test-Path $outputFile) {
            $remaining = Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
            if ($remaining.Length -gt $lastLength) {
                $remaining.Substring($lastLength) -split "`n" | ForEach-Object {
                    $line = $_.Trim(); if ($line) { Write-Status "WINCOPY: $line" }
                }
            }
            Remove-Item $outputFile -ErrorAction SilentlyContinue
        }
        if (Test-Path $errorFile) {
            $remErr = Get-Content $errorFile -Raw -ErrorAction SilentlyContinue
            if ($remErr.Length -gt $lastErrorLength) {
                $remErr.Substring($lastErrorLength) -split "`n" | ForEach-Object {
                    $eline = $_.Trim(); if ($eline) { Write-Status "WINCOPY: ERROR: $eline" }
                }
            }
            Remove-Item $errorFile -ErrorAction SilentlyContinue
        }

        # Determine success or failure based on robocopy exit code (0 or 1 are success)
        if ($exitCode -ge 8) {
            Write-CopyError -filePath $folderName -errorDescription "Robocopy reported failure (exit code $exitCode)" -action "failed"
            if ($script:progressDialogActive) { Close-WindowsProgressDialog }
            return $false
        }

        # Now close the progress dialog and report completion
        if ($script:progressDialogActive) {
            Close-WindowsProgressDialog
        }

        return $true
    } catch {
        Write-CopyError -filePath $folderName -errorDescription $_.Exception.Message -action "failed"
        return $false
    }
}

# Projects root for source projects (not destination)
    # $script:projectsRoot is set at startup (see top of file)

# GUI control variables
$script:form = $null
$script:browseButton = $null
$script:destinationTextBox = $null
$script:copyButton = $null
$script:cancelButton = $null
$script:statusTextBox = $null
$script:progressBar = $null
$script:tscanRadio = $null
$script:orthomosaicRadio = $null
$script:tscanGroupBox = $null
$script:mainFolderDropdown = $null
$script:subfolderDropdown = $null
$script:selectionCountLabel = $null

# OPTIMIZATION FUNCTIONS

function Get-AvailableProjects {
    param([string]$projectsRootPath = $script:projectsRoot)
    
    try {
        # Removed Write-Host to prevent popups in executable
        if (-not (Test-Path $projectsRootPath)) {
            # Removed Write-Host to prevent popups in executable
            return @()
        }
        
        # Removed Write-Host to prevent popups in executable
        $projects = Get-ChildItem $projectsRootPath -Directory -ErrorAction SilentlyContinue | Where-Object {
            # Exclude hidden/system folders and administrative folders (starting with ~)
            -not $_.Attributes.HasFlag([System.IO.FileAttributes]::Hidden) -and
            -not $_.Attributes.HasFlag([System.IO.FileAttributes]::System) -and
            -not $_.Name.StartsWith("~")
        } | ForEach-Object {
            # Removed Write-Host to prevent popups in executable
            [PSCustomObject]@{
                Name = $_.Name
                FullPath = $_.FullName
                LastModified = $_.LastWriteTime
                Size = 0  # Skip size calculation for now - too slow
            }
        }
        
        # Removed Write-Host to prevent popups in executable
        $sortedProjects = $projects | Sort-Object Name
        # Removed Write-Host to prevent popups in executable
        return $sortedProjects
    } catch {
        # Removed Write-Host to prevent popups in executable
        return @()
    }
}

# Global function for project search modal
function Show-ProjectSearchModal {
    param([string]$currentSourcePath = $script:sourceDir)
    
    # Removed Write-Host to prevent popups in executable
    
    # Create the modal form
    # Removed Write-Host to prevent popups in executable
    $script:searchForm = New-Object System.Windows.Forms.Form
    # Removed Write-Host to prevent popups in executable
    $script:searchForm.Text = "Search Projects"
    $script:searchForm.Size = New-Object System.Drawing.Size(700, 500)
    $script:searchForm.StartPosition = "CenterParent"
    $script:searchForm.FormBorderStyle = "FixedDialog"
    $script:searchForm.MaximizeBox = $false
    $script:searchForm.MinimizeBox = $false
    $script:searchForm.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    # Removed Write-Host to prevent popups in executable
    
    # Search box (now at top)
    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = "Search Projects:"
    $searchLabel.Location = New-Object System.Drawing.Point(20, 20)
    $searchLabel.Size = New-Object System.Drawing.Size(100, 20)
    $searchForm.Controls.Add($searchLabel)
    
    $script:searchTextBox = New-Object System.Windows.Forms.TextBox
    $script:searchTextBox.Location = New-Object System.Drawing.Point(130, 18)
    $script:searchTextBox.Size = New-Object System.Drawing.Size(400, 25)
    $script:searchTextBox.Text = "Type to search project names..."
    $script:searchTextBox.ForeColor = [System.Drawing.Color]::Gray
    $script:searchTextBox.Add_GotFocus({
        if ($script:searchTextBox.Text -eq "Type to search project names...") {
            $script:searchTextBox.Text = ""
            $script:searchTextBox.ForeColor = [System.Drawing.Color]::Black
        }
    })
    $script:searchTextBox.Add_LostFocus({
        if ($script:searchTextBox.Text -eq "") {
            $script:searchTextBox.Text = "Type to search project names..."
            $script:searchTextBox.ForeColor = [System.Drawing.Color]::Gray
        }
    })
    $script:searchForm.Controls.Add($script:searchTextBox)
    
    # Projects root configuration (now below search)
    $rootLabel = New-Object System.Windows.Forms.Label
    $rootLabel.Text = "Projects Root:"
    $rootLabel.Location = New-Object System.Drawing.Point(20, 60)
    $rootLabel.Size = New-Object System.Drawing.Size(100, 20)
    $searchForm.Controls.Add($rootLabel)
    
    $script:rootTextBox = New-Object System.Windows.Forms.TextBox
    $script:rootTextBox.Text = $script:projectsRoot
    $script:rootTextBox.Location = New-Object System.Drawing.Point(130, 58)
    $script:rootTextBox.Size = New-Object System.Drawing.Size(400, 25)
    $script:searchForm.Controls.Add($script:rootTextBox)
    
    $script:browseRootButton = New-Object System.Windows.Forms.Button
    $script:browseRootButton.Text = "Browse"
    $script:browseRootButton.Location = New-Object System.Drawing.Point(540, 58)
    $script:browseRootButton.Size = New-Object System.Drawing.Size(80, 25)
    $script:browseRootButton.Add_Click({
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Select Projects Root Directory"
        $folderBrowser.SelectedPath = $script:rootTextBox.Text
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:rootTextBox.Text = $folderBrowser.SelectedPath
            $script:projectsRoot = $folderBrowser.SelectedPath
            Refresh-ProjectList
        }
    })
    $script:searchForm.Controls.Add($script:browseRootButton)
    
    # Results list
    $resultsLabel = New-Object System.Windows.Forms.Label
    $resultsLabel.Text = "Available Projects:"
    $resultsLabel.Location = New-Object System.Drawing.Point(20, 100)
    $resultsLabel.Size = New-Object System.Drawing.Size(150, 20)
    $searchForm.Controls.Add($resultsLabel)
    
    $script:resultsListView = New-Object System.Windows.Forms.ListView
    $script:resultsListView.View = [System.Windows.Forms.View]::Details
    $script:resultsListView.FullRowSelect = $true
    $script:resultsListView.GridLines = $true
    $script:resultsListView.Location = New-Object System.Drawing.Point(20, 125)
    $script:resultsListView.Size = New-Object System.Drawing.Size(650, 250)
    $script:resultsListView.FullRowSelect = $true
    $script:resultsListView.GridLines = $false
    $script:resultsListView.Add_ColumnClick({ Sort-ListView $_.Column })
    
    # Add columns
    $script:resultsListView.Columns.Add("Project Name", 600)
    
    $script:searchForm.Controls.Add($script:resultsListView)
    
    # Buttons
    $selectButton = New-Object System.Windows.Forms.Button
    $selectButton.Text = "Select Project"
    $selectButton.Location = New-Object System.Drawing.Point(400, 390)
    $selectButton.Size = New-Object System.Drawing.Size(120, 35)
    $selectButton.Enabled = $false
    $selectButton.Add_Click({
        if ($resultsListView.SelectedItems.Count -gt 0) {
            $selectedProject = $resultsListView.SelectedItems[0].Tag
            $script:sourceDir = $selectedProject.FullPath
            $script:projectFolderName = $selectedProject.Name
            Update-SourceDisplay
            
            # Automatically set destination to C:\Projects\[ProjectName]
            Auto-DetectDestination
            
            # Update the main form's destination display
            if ($script:destinationTextBox) {
                $script:destinationTextBox.Text = $script:destinationDir
                $script:destinationTextBox.ForeColor = [System.Drawing.Color]::Blue
            }
            
            $searchForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            # Stop and dispose the search timer before closing
            if ($script:searchTimer) {
                $script:searchTimer.Stop()
                $script:searchTimer.Dispose()
            }
            $searchForm.Close()
        }
    })
    $searchForm.Controls.Add($selectButton)
    
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(540, 390)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 35)
    $cancelButton.Add_Click({ 
        # Stop and dispose the search timer before closing
        if ($script:searchTimer) {
            $script:searchTimer.Dispose()
        }
        $script:searchForm.Close() 
    })
    $searchForm.Controls.Add($cancelButton)
    
    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = "Refresh"
    $refreshButton.Location = New-Object System.Drawing.Point(20, 390)
    $refreshButton.Size = New-Object System.Drawing.Size(100, 35)
    $refreshButton.Add_Click({ Refresh-ProjectList })
    $searchForm.Controls.Add($refreshButton)
    
    # Status label
    $script:statusLabel = New-Object System.Windows.Forms.Label
    $script:statusLabel.Text = "Ready"
    $script:statusLabel.Location = New-Object System.Drawing.Point(140, 395)
    $script:statusLabel.Size = New-Object System.Drawing.Size(250, 20)
    $script:statusLabel.ForeColor = [System.Drawing.Color]::Blue
    $script:searchForm.Controls.Add($script:statusLabel)
    
    # Local functions for the modal
    function Refresh-ProjectList {
        $script:statusLabel.Text = "Loading projects..."
        $script:searchForm.Refresh()
        
        try {
            # Removed Write-Host to prevent popups in executable
            $projects = Get-AvailableProjects -projectsRootPath $script:rootTextBox.Text
            # Removed Write-Host to prevent popups in executable
            
            $script:resultsListView.Items.Clear()
            
            if ($projects.Count -eq 0) {
                $script:statusLabel.Text = "No projects found"
                $script:statusLabel.ForeColor = [System.Drawing.Color]::Orange
                return
            }
            
            # Show all projects for complete searchability
            # Removed Write-Host to prevent popups in executable
            
            foreach ($project in $projects) {
                $item = New-Object System.Windows.Forms.ListViewItem($project.Name)
                $item.Tag = $project
                $script:resultsListView.Items.Add($item) | Out-Null
            }
            
            $script:statusLabel.Text = "$($projects.Count) projects loaded"
            $script:statusLabel.ForeColor = [System.Drawing.Color]::Green
        } catch {
            # Removed Write-Host to prevent popups in executable
            $script:statusLabel.Text = "Error loading projects: $($_.Exception.Message)"
            $script:statusLabel.ForeColor = [System.Drawing.Color]::Red
        }
    }
    
    function Sort-ListView {
        param([System.Windows.Forms.ColumnClickEventArgs]$e)
        
        $column = $e.Column
        $listView = $e.ListView
        
        if ($listView.Tag -eq $column) {
            $listView.Sorting = if ($listView.Sorting -eq [System.Windows.Forms.SortOrder]::Ascending) { 
                [System.Windows.Forms.SortOrder]::Descending 
            } else { 
                [System.Windows.Forms.SortOrder]::Ascending 
            }
        } else {
            $listView.Sorting = [System.Windows.Forms.SortOrder]::Ascending
        }
        
        $listView.Tag = $column
        Sort-ListViewItems -listView $listView -column $column -sortOrder $listView.Sorting
    }
    
    # Search functionality with debouncing
    $script:searchTimer = New-Object System.Windows.Forms.Timer
    $script:searchTimer.Interval = 300
    $script:searchTimer.Add_Tick({
        $script:searchTimer.Stop()
        $searchText = $script:searchTextBox.Text.ToLower()
        # Removed Write-Host to prevent popups in executable
        
        if ($searchText.Length -eq 0) {
            # Removed Write-Host to prevent popups in executable
            # Show all items by refreshing the list
            Refresh-ProjectList
            return
        }
        
        # Removed Write-Host to prevent popups in executable
        # Filter items by removing non-matching ones
        $itemsToRemove = @()
        $matchCount = 0
        
        foreach ($item in $script:resultsListView.Items) {
            $projectName = $item.Text.ToLower()
            
            # Case-insensitive substring match, treat hyphens/underscores/spaces equivalently
            $normalizedName = $projectName -replace '[-_\s]', ''
            $normalizedSearch = $searchText -replace '[-_\s]', ''
            
            $isMatch = $projectName.Contains($searchText) -or 
                      $normalizedName.Contains($normalizedSearch)
            
            if ($isMatch) {
                $matchCount++
                # Removed Write-Host to prevent popups in executable
            } else {
                $itemsToRemove += $item
            }
        }
        
        # Removed Write-Host to prevent popups in executable
        
        # Remove non-matching items
        foreach ($item in $itemsToRemove) {
            $script:resultsListView.Items.Remove($item)
        }
        
        $visibleCount = $script:resultsListView.Items.Count
        if ($script:statusLabel) {
            $script:statusLabel.Text = "$visibleCount projects match search"
            $script:statusLabel.ForeColor = [System.Drawing.Color]::Blue
        }
        # Removed Write-Host to prevent popups in executable
    })
    
    $searchTextBox.Add_TextChanged({
        $searchTimer.Stop()
        $searchTimer.Start()
    })
    
    # ListView selection change
    $resultsListView.Add_SelectedIndexChanged({
        $selectButton.Enabled = $resultsListView.SelectedItems.Count -gt 0
    })
    
    # Double-click to select
    $resultsListView.Add_DoubleClick({
        if ($resultsListView.SelectedItems.Count -gt 0) {
            $selectButton.PerformClick()
        }
    })
    
    # Initial load
    # Removed Write-Host to prevent popups in executable
    Refresh-ProjectList
    # Removed Write-Host to prevent popups in executable
    
    # Show the modal
    # Removed Write-Host to prevent popups in executable
    $result = $script:searchForm.ShowDialog()
    # Removed Write-Host to prevent popups in executable
    return $result
}

# PowerShell-based ListView sorting function
function Sort-ListViewItems {
    param(
        [System.Windows.Forms.ListView]$listView,
        [int]$column,
        [System.Windows.Forms.SortOrder]$sortOrder
    )
    
    $items = @()
    foreach ($item in $listView.Items) {
        $items += $item
    }
    
    if ($sortOrder -eq [System.Windows.Forms.SortOrder]::Ascending) {
        $sortedItems = $items | Sort-Object { $_.SubItems[$column].Text }
    } else {
        $sortedItems = $items | Sort-Object { $_.SubItems[$column].Text } -Descending
    }
    
    $listView.Items.Clear()
    foreach ($item in $sortedItems) {
        $listView.Items.Add($item) | Out-Null
    }
}

function Update-SourceDisplay {
    if ($script:infoLabel) {
        $script:infoLabel.Text = "Project: $($script:projectFolderName)`nSource: $($script:sourceDir)"
    }
    
    # Enable copy mode selection when a project is selected
    Enable-CopyModeSelection
}

function Enable-CopyModeSelection {
    # Enable all copy mode radio buttons when a project is selected
    if ($script:initialCloudRadio) { $script:initialCloudRadio.Enabled = $true }
    if ($script:terrascanRadio) { $script:terrascanRadio.Enabled = $true }
    if ($script:orthomosaicRadio) { $script:orthomosaicRadio.Enabled = $true }
    if ($script:tscanRadio) { $script:tscanRadio.Enabled = $true }
    
    # Update the instruction label to show copy modes are now available
    if ($script:copyModeInstructionLabel) {
        $script:copyModeInstructionLabel.Text = "SUCCESS: Copy modes are now available - select your preferred option below"
        $script:copyModeInstructionLabel.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    
    # Refresh Terrascan Tscan subfolder list if Terrascan mode is currently selected
    if ($script:terrascanRadio -and $script:terrascanRadio.Checked -and $script:terrascanTscanCheckList) {
        $script:terrascanTscanCheckList.Items.Clear()
        $terrascanSubfolders = Get-TerrascanTscanSubfolders
        if ($terrascanSubfolders -and $terrascanSubfolders.Count -gt 0) {
            foreach ($subfolder in $terrascanSubfolders) {
                $script:terrascanTscanCheckList.Items.Add($subfolder) | Out-Null
            }
            $script:terrascanTscanCheckList.Enabled = $true
        } else {
            $script:terrascanTscanCheckList.Items.Add("No Tscan subfolders found") | Out-Null
            $script:terrascanTscanCheckList.Enabled = $false
        }
    }
}

function Get-DriveType {
    param([string]$path)

    # UNC paths are network shares
    if ($path -and $path -like '\\\\*') { return 'Network' }

    try {
        $driveLetter = (Get-Item $path).PSDrive.Name + ":"
        $driveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $driveLetter }
        
        switch ($driveInfo.DriveType) {
            3 { return "HDD" }      # Hard Disk
            4 { return "Network" }  # Network Drive
            5 { return "CD/DVD" }   # CD/DVD
            default { 
                # Check if it's SSD by looking at media type
                try {
                    $physicalDisk = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq $driveInfo.DeviceID }
                    if ($physicalDisk.MediaType -eq "SSD") {
                        return "SSD"
                    }
                } catch {
                    # Fallback: assume SSD if access time is very fast
                    $testStart = Get-Date
                    $null = Get-ChildItem $path -ErrorAction SilentlyContinue | Select-Object -First 1
                    $testTime = ((Get-Date) - $testStart).TotalMilliseconds
                    if ($testTime -lt 10) {
                        return "SSD"
                    }
                }
                return "HDD"
            }
        }
    } catch {
        return "Unknown"
    }
}

function Get-OptimalRobocopyParams {
    param([string]$sourceType, [string]$destType, [int]$fileCount = 1000)
    
    # Determine optimal parameters based on drive types and file count
    if ($sourceType -eq "SSD" -and $destType -eq "SSD") {
        # SSD to SSD - Maximum aggression
        $threads = if ($fileCount -gt 50000) { 128 } elseif ($fileCount -gt 10000) { 64 } else { 32 }
        return @{
            Threads = $threads
            Params = "/E /MT:$threads /R:0 /W:0 /J /COPY:DAT /NP /NDL /NC /XO"
            Description = "SSD-to-SSD Optimized: Unbuffered I/O, Max threads, No retries, Overwrite newer files"
        }
    }
    elseif ($sourceType -eq "Network" -or $destType -eq "Network") {
        # Network involved - Conservative approach
        return @{
            Threads = 8
            Params = "/E /MT:8 /R:2 /W:2 /Z /NP /NDL /NC /XO"
            Description = "Network Optimized: Restartable mode, Low threads, Retry logic, Overwrite newer files"
        }
    }
    elseif ($sourceType -eq "HDD" -and $destType -eq "HDD") {
        # HDD to HDD - Balanced approach
        $threads = if ($fileCount -gt 10000) { 16 } else { 8 }
        return @{
            Threads = $threads
            Params = "/E /MT:$threads /R:1 /W:1 /COPY:DAT /NP /NDL /NC /XO"
            Description = "HDD-to-HDD Optimized: Balanced threads, Minimal retries, Overwrite newer files"
        }
    }
    else {
        # Mixed (SSD-HDD) - Moderate approach
        return @{
            Threads = 32
            Params = "/E /MT:32 /R:1 /W:1 /J /COPY:DAT /NP /NDL /NC /XO"
            Description = "Mixed Drive Optimized: Medium threads, Unbuffered I/O, Overwrite newer files"
        }
    }
}

function Start-DirectCopy {
    param([array]$folderList, [string]$sourceBase, [string]$destBase)
    
    Write-Status "DEBUG: Start-DirectCopy called with $($folderList.Count) folders"
    Write-Status "DEBUG: Source base: $sourceBase"
    Write-Status "DEBUG: Destination base: $destBase"
    Write-Status "DEBUG: Folders to process: $($folderList -join ', ')"
    
    Write-Status "=== STARTING DIRECT COPY (NO BACKGROUND JOBS) ==="
    Write-Status "COPY: Processing $($folderList.Count) folders sequentially"
    
    # Initialize tracking
    $script:activeProcesses = @()
    $script:copyResults = @()
    $totalFolders = $folderList.Count
    $completedFolders = 0
    
    foreach ($folder in $folderList) {
        if ($script:cancelRequested) {
            Write-Status "COPY: Cancellation requested, stopping copy process"
            break
        }
        
        $completedFolders++
        $sourcePath = Join-Path $sourceBase $folder
        $destPath = Join-Path $destBase $folder
        
        Write-Status "DEBUG: Processing folder ${completedFolders}/${totalFolders}: '$folder'"
        Write-Status "DEBUG: Source path: $sourcePath"
        Write-Status "DEBUG: Destination path: $destPath"
        
        # Update progress
        $progressPercent = [math]::Round(($completedFolders / $totalFolders) * 100)
        Update-Progress $progressPercent
        Write-Status "COPY: [$progressPercent%] Processing '$folder' ($completedFolders of $totalFolders)"
        
        if (Test-Path $sourcePath) {
            Write-Status "DEBUG: Source path exists, checking contents..."
            # Verify source has content
            $sourceItems = Get-ChildItem $sourcePath -ErrorAction SilentlyContinue
            Write-Status "DEBUG: Found $($sourceItems.Count) items in source folder"
            
            if (-not $sourceItems -or $sourceItems.Count -eq 0) {
                Write-Status "DEBUG: Source folder is empty, skipping"
                Write-Status "COPY: Skipping '$folder' - source folder is empty"
                continue
            }
            
            Write-Status "DEBUG: Source folder has content, starting robocopy"
            Write-Status "COPY: Copying '$folder' ($($sourceItems.Count) items)..."
            
            # Create destination directory if needed
            $destParent = Split-Path $destPath -Parent
            if (-not (Test-Path $destParent)) {
                try {
                    Write-Status "DEBUG: Creating destination parent: $destParent"
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                    Write-Status "DEBUG: Successfully created destination parent"
                } catch {
                    Write-Status "DEBUG: ERROR - Cannot create destination directory: $($_.Exception.Message)"
                    Write-Status "COPY: ERROR - Cannot create destination for '$folder' - $($_.Exception.Message)"
                    continue
                }
            }
            
            # Create robocopy process
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = "robocopy"
            $processInfo.Arguments = "`"$sourcePath`" `"$destPath`" $($script:optimalParams)"
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            
            Write-Status "DEBUG: Robocopy command: robocopy $($processInfo.Arguments)"
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            
            try {
                $startTime = Get-Date
                Write-Status "DEBUG: Starting robocopy process for '$folder' at $startTime"
                
                $processStarted = $process.Start()
                Write-Status "DEBUG: Process started successfully - PID: $($process.Id)"
                
                # Add to active processes for cleanup
                $script:activeProcesses += $process
                
                # Wait for completion with progress updates
                $processTimeout = 2147483647  # effectively no timeout
                $checkInterval = 1000     # 1 second
                $elapsedTime = 0
                
                while (-not $process.HasExited -and $elapsedTime -lt $processTimeout -and -not $script:cancelRequested) {
                    Start-Sleep -Milliseconds $checkInterval
                    $elapsedTime += $checkInterval
                    
                    # Update UI every 5 seconds
                    if (($elapsedTime % 5000) -eq 0) {
                        $elapsedSeconds = [math]::Round($elapsedTime / 1000)
                        Write-Status "COPY: Still copying '$folder' - ${elapsedSeconds}s elapsed..."
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                }
                
                if ($script:cancelRequested) {
                    Write-Status "DEBUG: Cancellation requested, killing process"
                    try {
                        $process.Kill()
                        Write-Status "DEBUG: Process killed due to cancellation"
                    } catch {
                        Write-Status "DEBUG: Error killing process: $($_.Exception.Message)"
                    }
                    break
                }
                
                if (-not $process.HasExited) {
                    Write-Status "DEBUG: Process timed out after 5 minutes, killing"
                    try {
                        $process.Kill()
                        Write-Status "DEBUG: Process killed due to timeout"
                        Write-Status "COPY: ERROR - '$folder' timed out after 5 minutes"
                    } catch {
                        Write-Status "DEBUG: Error killing timed-out process: $($_.Exception.Message)"
                    }
                } else {
                    $endTime = Get-Date
                    $duration = ($endTime - $startTime).TotalSeconds
                    $exitCode = $process.ExitCode
                    
                    Write-Status "DEBUG: Process completed - Exit code: $exitCode, Duration: ${duration}s"
                    
                    # Interpret robocopy exit codes
                    $isSuccess = ($exitCode -le 3)
                    $exitCodeMeaning = switch ($exitCode) {
                        0 { "No files copied (no action needed)" }
                        1 { "Files copied successfully" }
                        2 { "Extra files/folders detected" }
                        3 { "Some files copied, some skipped" }
                        4 { "Some mismatched files/folders" }
                        5 { "Some files copied, some mismatched" }
                        6 { "Extra files/folders and mismatched files" }
                        7 { "Files copied, extra files/folders, and mismatched files" }
                        8 { "Some files failed to copy" }
                        default { "Error or unknown exit code" }
                    }
                    
                    if ($isSuccess) {
                        Write-Status "COPY: SUCCESS - '$folder' completed in ${duration}s - $exitCodeMeaning"
                    } else {
                        Write-Status "COPY: WARNING - '$folder' completed with issues (Exit: $exitCode) - $exitCodeMeaning"
                    }
                }
                
                # Clean up process
                try {
                    $process.Dispose()
                    Write-Status "DEBUG: Process disposed successfully"
                } catch {
                    Write-Status "DEBUG: Error disposing process: $($_.Exception.Message)"
                }
                
                # Remove from active processes
                $script:activeProcesses = $script:activeProcesses | Where-Object { $_.Id -ne $process.Id }
                
            } catch {
                Write-Status "DEBUG: EXCEPTION during robocopy execution: $($_.Exception.Message)"
                Write-Status "COPY: ERROR - Exception copying '$folder': $($_.Exception.Message)"
                
                try {
                    $process.Dispose()
                } catch {
                    Write-Status "DEBUG: Error disposing process after exception: $($_.Exception.Message)"
                }
            }
            
        } else {
            Write-Status "DEBUG: Source path does not exist: $sourcePath"
            Write-Status "COPY: SKIPPING '$folder' - source not found"
        }
        
        # Small delay between folders
        Start-Sleep -Milliseconds 500
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    Write-Status "DEBUG: Copy process completed"
    Write-Status "COPY: All folders processed"
    
    # Final progress update
    Update-Progress 100
    
    # Reset UI state
    $script:copyButton.Enabled = $true
    $script:cancelButton.Enabled = $false
    
    Write-Status "COPY: Copy operation completed successfully!"
}

function Monitor-ParallelProgress {
    if ($script:parallelJobs.Count -eq 0) { return }
    
    # Initialize monitoring variables
    $script:completedJobs = 0
    $script:totalJobs = $script:parallelJobs.Count
    $script:processedJobs = @()
    $script:jobHangTimes = @{}
    $script:maxJobTimeout = 300  # 5 minutes per job
    $script:hangDetectionPeriod = 30  # 30 seconds without progress = hang
    $script:lastProgressUpdate = Get-Date
    
    Write-Status "PROGRESS: Monitoring $($script:totalJobs) parallel copy jobs..."
    Write-Status "PROGRESS: DEBUG - Job monitoring started at $(Get-Date)"
    Write-Status "PROGRESS: DEBUG - Hang detection: $($script:hangDetectionPeriod) seconds, Job timeout: $($script:maxJobTimeout) seconds"
    
    # Create and start monitoring timer
    $script:monitoringTimer = New-Object System.Windows.Forms.Timer
    $script:monitoringTimer.Interval = 1000  # Check every 1 second
    $script:monitoringTimer.Add_Tick({ Check-JobProgress })
    $script:monitoringTimer.Start()
    
    Write-Status "PROGRESS: Started timer-based monitoring to keep UI responsive"
}

function Check-JobProgress {
    Write-Status "DEBUG: Check-JobProgress called at $(Get-Date)"
    Write-Status "DEBUG: cancelRequested=$($script:cancelRequested), completedJobs=$($script:completedJobs), totalJobs=$($script:totalJobs)"
    
    if ($script:cancelRequested -or $script:completedJobs -ge $script:totalJobs) {
        Write-Status "DEBUG: Stopping monitoring timer - cancelRequested=$($script:cancelRequested), completedJobs=$($script:completedJobs), totalJobs=$($script:totalJobs)"
        $script:monitoringTimer.Stop()
        $script:monitoringTimer.Dispose()
        Write-Status "PROGRESS: Monitoring timer stopped"
        return
    }
    
    try {
        Write-Status "DEBUG: Starting job progress check..."
        $script:completedJobs = 0
        $runningJobs = 0
        $failedJobs = 0
        $hungJobs = 0
        $progressUpdated = $false
        
        Write-Status "DEBUG: Checking $($script:parallelJobs.Count) parallel jobs..."
        
        foreach ($jobInfo in $script:parallelJobs) {
            $job = $jobInfo.Job
            $folderName = $jobInfo.FolderName
            $jobId = $jobInfo.JobId
            
            Write-Status "DEBUG: Processing job $jobId ($folderName) - Current State: $($job.State)"
            
            # Skip if already processed
            if ($script:processedJobs -contains $jobId) {
                Write-Status "DEBUG: Job $jobId already processed, skipping"
                $script:completedJobs++
                continue
            }
            
            # Check for job timeout
            $elapsed = ((Get-Date) - $jobInfo.StartTime).TotalSeconds
            Write-Status "DEBUG: Job $jobId elapsed time: $([math]::Round($elapsed))s (max timeout: $($script:maxJobTimeout)s)"
            
            if ($elapsed -gt $script:maxJobTimeout -and $job.State -eq "Running") {
                Write-Status "DEBUG: Job $jobId timed out - attempting to terminate"
                Write-Status "PROGRESS: TIMEOUT - Job $jobId ($folderName) has been running for $([math]::Round($elapsed))s - forcing termination"
                
                # Force kill the robocopy process
                try {
                    Write-Status "DEBUG: Searching for robocopy processes for $folderName"
                    $jobProcesses = Get-WmiObject Win32_Process | Where-Object { $_.ProcessName -eq "robocopy.exe" -and $_.CommandLine -like "*$folderName*" }
                    Write-Status "DEBUG: Found $($jobProcesses.Count) robocopy processes for $folderName"
                    foreach ($proc in $jobProcesses) {
                        Write-Status "DEBUG: Terminating robocopy process PID $($proc.ProcessId) for $folderName"
                        Write-Status "PROGRESS: KILL - Terminating robocopy process PID $($proc.ProcessId) for $folderName"
                        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    Write-Status "DEBUG: Error killing robocopy process for $folderName - $($_.Exception.Message)"
                    Write-Status "PROGRESS: ERROR - Could not kill robocopy process for $folderName"
                }
                
                # Stop and remove the job
                try {
                    Write-Status "DEBUG: Stopping and removing job $jobId"
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    Write-Status "DEBUG: Job $jobId stopped and removed successfully"
                    Write-Status "PROGRESS: TIMEOUT - Job $jobId terminated due to timeout"
                } catch {
                    Write-Status "DEBUG: Error stopping job $jobId - $($_.Exception.Message)"
                    Write-Status "PROGRESS: ERROR - Could not stop timed-out job $jobId"
                }
                
                $script:completedJobs++
                $script:processedJobs += $jobId
                $progressUpdated = $true
                Write-Status "DEBUG: Job $jobId marked as completed due to timeout"
                continue
            }
            
            if ($job.State -eq "Completed") {
                Write-Status "DEBUG: Job $jobId is in Completed state"
                $script:completedJobs++
                $script:processedJobs += $jobId
                $progressUpdated = $true
                
                # Get job results with enhanced error handling
                try {
                    Write-Status "DEBUG: Job $jobId - Checking for job data..."
                    if ($job.HasMoreData) {
                        Write-Status "DEBUG: Job $jobId - Has data, receiving job results..."
                        $result = Receive-Job -Job $job -ErrorAction Stop
                        Write-Status "DEBUG: Job $jobId - Job result received: $($result -ne $null)"
                        
                        if ($result -and $result.PSObject.Properties.Name -contains 'Success') {
                            Write-Status "DEBUG: Job $jobId - Result has Success property: $($result.Success)"
                            if ($result.Success) {
                                $duration = if ($result.Duration) { " ($($result.Duration)s)" } else { "" }
                                $exitCodeInfo = if ($result.ExitCodeMeaning) { " - $($result.ExitCodeMeaning)" } else { "" }
                                Write-Status "DEBUG: Job $jobId - Success with duration: $duration, exit code info: $exitCodeInfo"
                                Write-Status "PROGRESS: OK $folderName completed successfully$duration$exitCodeInfo"
                            } else {
                                $exitCode = if ($result.ExitCode) { $result.ExitCode } else { "Unknown" }
                                $errorMsg = if ($result.Error) { $result.Error } else { "No error details" }
                                Write-Status "DEBUG: Job $jobId - Failed with exit code: $exitCode, error: $errorMsg"
                                Write-Status "PROGRESS: ERROR $folderName failed (Exit: ${exitCode}) - $errorMsg"
                            }
                        } else {
                            Write-Status "DEBUG: Job $jobId - Result is null or missing Success property"
                            Write-Status "PROGRESS: ERROR $folderName failed - malformed job result"
                        }
                    } else {
                        Write-Status "DEBUG: Job $jobId - No data available from completed job"
                        Write-Status "PROGRESS: ERROR $folderName failed - job completed but no data"
                    }
                    
                    Write-Status "DEBUG: Job $jobId - Removing job from queue..."
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    Write-Status "DEBUG: Job $jobId - Job removed successfully"
                } catch {
                    Write-Status "DEBUG: Job $jobId - Exception during job processing: $($_.Exception.Message)"
                    Write-Status "PROGRESS: ERROR $folderName job processing failed - $($_.Exception.Message)"
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                }
            }
            elseif ($job.State -eq "Running") {
                Write-Status "DEBUG: Job $jobId is in Running state"
                $runningJobs++
                
                # Check for hang detection
                if (-not $script:jobHangTimes.ContainsKey($jobId)) {
                    Write-Status "DEBUG: Job $jobId - Initializing hang detection timing"
                    $script:jobHangTimes[$jobId] = @{
                        LastCheck = Get-Date
                        ConsecutiveNoProgress = 0
                    }
                }
                
                $timeSinceLastCheck = ((Get-Date) - $script:jobHangTimes[$jobId].LastCheck).TotalSeconds
                Write-Status "DEBUG: Job $jobId - Time since last check: $([math]::Round($timeSinceLastCheck))s (hang period: $($script:hangDetectionPeriod)s)"
                
                if ($timeSinceLastCheck -gt $script:hangDetectionPeriod) {
                    Write-Status "DEBUG: Job $jobId - Hang detection period exceeded, incrementing counter"
                    $script:jobHangTimes[$jobId].ConsecutiveNoProgress++
                    $script:jobHangTimes[$jobId].LastCheck = Get-Date
                    
                    Write-Status "PROGRESS: HANG CHECK - Job $jobId ($folderName) - No progress for $([math]::Round($timeSinceLastCheck))s (Check #$($script:jobHangTimes[$jobId].ConsecutiveNoProgress))"
                    
                    # Check if robocopy process is still running
                    try {
                        Write-Status "DEBUG: Job $jobId - Checking for robocopy processes..."
                        $jobProcesses = Get-WmiObject Win32_Process | Where-Object { $_.ProcessName -eq "robocopy.exe" -and $_.CommandLine -like "*$folderName*" }
                        Write-Status "DEBUG: Job $jobId - Found $($jobProcesses.Count) robocopy processes for $folderName"
                        
                        foreach ($proc in $jobProcesses) {
                            Write-Status "DEBUG: Job $jobId - Robocopy process PID $($proc.ProcessId) is running"
                        }
                    } catch {
                        Write-Status "DEBUG: Job $jobId - Error checking robocopy processes: $($_.Exception.Message)"
                    }
                    
                    # If job has been hanging for too long, force termination
                    if ($script:jobHangTimes[$jobId].ConsecutiveNoProgress -gt 3) {
                        Write-Status "DEBUG: Job $jobId - Hang threshold exceeded, forcing termination"
                        Write-Status "PROGRESS: HANG DETECTED - Job $jobId ($folderName) appears to be hung - forcing termination"
                        
                        # Force kill the robocopy process
                        try {
                            Write-Status "DEBUG: Job $jobId - Searching for robocopy processes to terminate..."
                            $jobProcesses = Get-WmiObject Win32_Process | Where-Object { $_.ProcessName -eq "robocopy.exe" -and $_.CommandLine -like "*$folderName*" }
                            Write-Status "DEBUG: Job $jobId - Found $($jobProcesses.Count) robocopy processes to terminate"
                            
                            foreach ($proc in $jobProcesses) {
                                Write-Status "DEBUG: Job $jobId - Terminating robocopy process PID $($proc.ProcessId)"
                                Write-Status "PROGRESS: KILL - Terminating hung robocopy process PID $($proc.ProcessId) for $folderName"
                                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                            }
                        } catch {
                            Write-Status "DEBUG: Job $jobId - Error terminating robocopy processes: $($_.Exception.Message)"
                            Write-Status "PROGRESS: ERROR - Could not kill hung robocopy process for $folderName"
                        }
                        
                        # Stop and remove the job
                        try {
                            Write-Status "DEBUG: Job $jobId - Stopping and removing hung job..."
                            Stop-Job -Job $job -ErrorAction SilentlyContinue
                            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                            Write-Status "DEBUG: Job $jobId - Hung job stopped and removed"
                            Write-Status "PROGRESS: HANG - Job $jobId terminated due to hang detection"
                        } catch {
                            Write-Status "DEBUG: Job $jobId - Error stopping hung job: $($_.Exception.Message)"
                            Write-Status "PROGRESS: ERROR - Could not stop hung job $jobId"
                        }
                        
                        $script:completedJobs++
                        $script:processedJobs += $jobId
                        $progressUpdated = $true
                        Write-Status "DEBUG: Job $jobId - Marked as completed due to hang detection"
                        continue
                    }
                } else {
                    Write-Status "DEBUG: Job $jobId - Still within hang detection period, continuing normally"
                }
            }
            elseif ($job.State -eq "Failed") {
                $script:completedJobs++
                $failedJobs++
                $script:processedJobs += $jobId
                $progressUpdated = $true
                
                # Get failure details
                try {
                    $jobError = $job.ChildJobs[0].JobStateInfo.Reason
                    if ($jobError) {
                        Write-Status "PROGRESS: ERROR $folderName job failed - $($jobError.Message)"
                    } else {
                        Write-Status "PROGRESS: ERROR $folderName job failed - no error details available"
                    }
                } catch {
                    Write-Status "PROGRESS: ERROR $folderName job failed - could not get error details"
                }
                
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
        
        # Update progress tracking
        if ($progressUpdated) {
            $script:lastProgressUpdate = Get-Date
        }
        
        # Check for global hang condition
        $globalHangTime = ((Get-Date) - $script:lastProgressUpdate).TotalSeconds
        if ($globalHangTime -gt 120 -and $runningJobs -gt 0) {
            Write-Status "PROGRESS: GLOBAL HANG - No progress for $([math]::Round($globalHangTime))s with $runningJobs running jobs"
            Write-Status "PROGRESS: GLOBAL HANG - Detailed job states:"
            foreach ($jobInfo in $script:parallelJobs) {
                Write-Status "PROGRESS: HANG - Job $($jobInfo.JobId) ($($jobInfo.FolderName)): State=$($jobInfo.Job.State), StartTime=$($jobInfo.StartTime)"
            }
            return
        }
        
        Write-Status "DEBUG: Job processing complete - completedJobs=$($script:completedJobs), runningJobs=$runningJobs, failedJobs=$failedJobs, hungJobs=$hungJobs"
        Write-Status "DEBUG: Progress updated: $progressUpdated"
        
        # Update progress
        $progressPercent = if ($script:totalJobs -gt 0) { [math]::Round(($script:completedJobs / $script:totalJobs) * 100) } else { 100 }
        Write-Status "DEBUG: Calculated progress: $progressPercent percent ($($script:completedJobs) / $($script:totalJobs))"
        
        Update-Progress $progressPercent
        Write-Status "DEBUG: Progress bar updated to $progressPercent percent"
        
        $statusMsg = "PROGRESS: $($script:completedJobs) of $($script:totalJobs) completed ($runningJobs running, $failedJobs failed"
        if ($hungJobs -gt 0) {
            $statusMsg += ", $hungJobs hung"
        }
        $statusMsg += ") - $progressPercent percent"
        Write-Status $statusMsg
        
        # Check if all jobs are complete
        if ($script:completedJobs -ge $script:totalJobs) {
            Write-Status "DEBUG: All jobs completed - stopping monitoring timer"
            Write-Status "PROGRESS: All jobs completed - stopping monitoring timer"
            $script:monitoringTimer.Stop()
            $script:monitoringTimer.Dispose()
            
            # Reset UI state
            $script:copyButton.Enabled = $true
            $script:cancelButton.Enabled = $false
            $script:progressBar.Value = 100
            
            Write-Status "DEBUG: UI state reset after completion"
            Write-Status "PROGRESS: Copy operation completed successfully!"
        } else {
            Write-Status "DEBUG: Jobs still running - continuing monitoring"
        }
        
    } catch {
        Write-Status "DEBUG: EXCEPTION in Check-JobProgress: $($_.Exception.Message)"
        Write-Status "DEBUG: Exception type: $($_.Exception.GetType().Name)"
        Write-Status "DEBUG: Stack trace: $($_.Exception.StackTrace)"
        Write-Status "PROGRESS: ERROR in monitoring timer - $($_.Exception.Message)"
        Write-Status "PROGRESS: Stopping monitoring due to error"
        
        try {
            $script:monitoringTimer.Stop()
            $script:monitoringTimer.Dispose()
            Write-Status "DEBUG: Monitoring timer stopped after exception"
        } catch {
            Write-Status "DEBUG: Error stopping monitoring timer: $($_.Exception.Message)"
        }
        
        # Reset UI state on error
        $script:copyButton.Enabled = $true
        $script:cancelButton.Enabled = $false
        Write-Status "DEBUG: UI state reset after exception"
    }
}

function Monitor-ParallelProgress-Legacy {
    # Legacy blocking version - keeping for reference but not used
    if ($script:parallelJobs.Count -eq 0) { return }
    
    $completedJobs = 0
    $totalJobs = $script:parallelJobs.Count
    $processedJobs = @()
    $jobHangTimes = @{}
    $maxJobTimeout = 300  # 5 minutes per job
    $hangDetectionPeriod = 30  # 30 seconds without progress = hang
    $lastProgressUpdate = Get-Date
    
    Write-Status "PROGRESS: Monitoring $totalJobs parallel copy jobs..."
    Write-Status "PROGRESS: DEBUG - Job monitoring started at $(Get-Date)"
    Write-Status "PROGRESS: DEBUG - Hang detection: $hangDetectionPeriod seconds, Job timeout: $maxJobTimeout seconds"
    
    while ($completedJobs -lt $totalJobs -and -not $script:cancelRequested) {
        $completedJobs = 0
        $runningJobs = 0
        $failedJobs = 0
        $hungJobs = 0
        $progressUpdated = $false
        
        foreach ($jobInfo in $script:parallelJobs) {
            $job = $jobInfo.Job
            $folderName = $jobInfo.FolderName
            $jobId = $jobInfo.JobId
            
            # Skip if already processed
            if ($processedJobs -contains $jobId) {
                $completedJobs++
                continue
            }
            
            # Check for job timeout
            $elapsed = ((Get-Date) - $jobInfo.StartTime).TotalSeconds
            if ($elapsed -gt $maxJobTimeout -and $job.State -eq "Running") {
                Write-Status "PROGRESS: TIMEOUT - Job $jobId ($folderName) has been running for $([math]::Round($elapsed))s - forcing termination"
                
                # Force kill the robocopy process
                try {
                    $jobProcesses = Get-WmiObject Win32_Process | Where-Object { $_.ProcessName -eq "robocopy.exe" -and $_.CommandLine -like "*$folderName*" }
                    foreach ($proc in $jobProcesses) {
                        Write-Status "PROGRESS: KILL - Terminating robocopy process PID $($proc.ProcessId) for $folderName"
                        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    Write-Status "PROGRESS: ERROR - Could not kill robocopy process for $folderName"
                }
                
                # Stop and remove the job
                try {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    Write-Status "PROGRESS: TIMEOUT - Job $jobId terminated due to timeout"
                } catch {
                    Write-Status "PROGRESS: ERROR - Could not stop timed-out job $jobId"
                }
                
                $completedJobs++
                $processedJobs += $jobId
                $progressUpdated = $true
                continue
            }
            
            Write-Status "PROGRESS: DEBUG - Checking job $jobId ($folderName) - State: $($job.State) - Elapsed: $([math]::Round($elapsed))s"
            
            if ($job.State -eq "Completed") {
                $completedJobs++
                $processedJobs += $jobId
                $progressUpdated = $true
                
                Write-Status "PROGRESS: DEBUG - Job $jobId completed, retrieving results..."
                
                # Get job results with enhanced error handling
                try {
                    # Check if job has results
                    if ($job.HasMoreData) {
                        Write-Status "PROGRESS: DEBUG - Job $jobId has data available"
                        $result = Receive-Job -Job $job -ErrorAction Stop
                        Write-Status "PROGRESS: DEBUG - Job $jobId result retrieved successfully"
                        
                        # Enhanced result validation
                        if ($result) {
                            Write-Status "PROGRESS: DEBUG - Job $jobId result is not null"
                            
                            # Check if result has expected properties
                            if ($result.PSObject.Properties.Name -contains 'Success') {
                                Write-Status "PROGRESS: DEBUG - Job $jobId result has Success property: $($result.Success)"
                                
                                if ($result.Success) {
                                    $duration = if ($result.Duration) { " ($($result.Duration)s)" } else { "" }
                                    $exitCodeInfo = if ($result.ExitCodeMeaning) { " - $($result.ExitCodeMeaning)" } else { "" }
                                    Write-Status "PROGRESS: OK $folderName completed successfully$duration$exitCodeInfo"
                                } else {
                                    $exitCode = if ($result.ExitCode) { $result.ExitCode } else { "Unknown" }
                                    $errorMsg = if ($result.Error) { $result.Error } else { "No error details" }
                                    Write-Status "PROGRESS: ERROR $folderName failed (Exit: ${exitCode}) - $errorMsg"
                                    
                                    # Show debug info if available
                                    if ($result.DebugInfo) {
                                        Write-Status "PROGRESS: DEBUG INFO for ${folderName}:"
                                        foreach ($debugLine in $result.DebugInfo) {
                                            Write-Status "PROGRESS: $debugLine"
                                        }
                                    }
                                }
                            } else {
                                Write-Status "PROGRESS: DEBUG - Job $jobId result missing Success property"
                                Write-Status "PROGRESS: DEBUG - Available properties: $($result.PSObject.Properties.Name -join ', ')"
                                Write-Status "PROGRESS: ERROR $folderName failed - malformed job result"
                            }
                        } else {
                            Write-Status "PROGRESS: DEBUG - Job $jobId result is null"
                            Write-Status "PROGRESS: ERROR $folderName failed - no result returned from job"
                        }
                    } else {
                        Write-Status "PROGRESS: DEBUG - Job $jobId has no data available"
                        Write-Status "PROGRESS: ERROR $folderName failed - job completed but no data"
                    }
                    
                    # Clean up job
                    try {
                        Remove-Job -Job $job -Force -ErrorAction Stop
                        Write-Status "PROGRESS: DEBUG - Job $jobId cleaned up successfully"
                    } catch {
                        Write-Status "PROGRESS: DEBUG - Error cleaning up job ${jobId}: $($_.Exception.Message)"
                    }
                    
                } catch {
                    Write-Status "PROGRESS: DEBUG - Exception processing job ${jobId}: $($_.Exception.Message)"
                    Write-Status "PROGRESS: DEBUG - Exception type: $($_.Exception.GetType().Name)"
                    Write-Status "PROGRESS: ERROR $folderName job processing failed - $($_.Exception.Message)"
                    
                    # Try to get error details from job
                    try {
                        $jobError = $job.ChildJobs[0].JobStateInfo.Reason
                        if ($jobError) {
                            Write-Status "PROGRESS: DEBUG - Job error details: $($jobError.Message)"
                        }
                    } catch {
                        Write-Status "PROGRESS: DEBUG - Could not get job error details"
                    }
                    
                    # Clean up failed job
                    try {
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    } catch {
                        # Ignore cleanup errors for failed jobs
                    }
                }
            }
            elseif ($job.State -eq "Running") {
                $runningJobs++
                
                # Check for hang detection
                if (-not $jobHangTimes.ContainsKey($jobId)) {
                    $jobHangTimes[$jobId] = @{
                        LastCheck = Get-Date
                        ConsecutiveNoProgress = 0
                    }
                }
                
                $timeSinceLastCheck = ((Get-Date) - $jobHangTimes[$jobId].LastCheck).TotalSeconds
                if ($timeSinceLastCheck -gt $hangDetectionPeriod) {
                    $jobHangTimes[$jobId].ConsecutiveNoProgress++
                    $jobHangTimes[$jobId].LastCheck = Get-Date
                    
                    Write-Status "PROGRESS: HANG CHECK - Job $jobId ($folderName) - No progress for $([math]::Round($timeSinceLastCheck))s (Check #$($jobHangTimes[$jobId].ConsecutiveNoProgress))"
                    
                    # Check if robocopy process is still responsive
                    try {
                        $jobProcesses = Get-WmiObject Win32_Process | Where-Object { $_.ProcessName -eq "robocopy.exe" -and $_.CommandLine -like "*$folderName*" }
                        if ($jobProcesses) {
                            foreach ($proc in $jobProcesses) {
                                Write-Status "PROGRESS: PROCESS CHECK - Robocopy PID $($proc.ProcessId) for $folderName is running"
                                # Check CPU usage to see if it's actually working
                                try {
                                    $cpuUsage = Get-WmiObject Win32_PerfRawData_PerfProc_Process | Where-Object { $_.IDProcess -eq $proc.ProcessId }
                                    if ($cpuUsage) {
                                        Write-Status "PROGRESS: CPU - Process $($proc.ProcessId) CPU usage detected"
                                    }
                                } catch {
                                    Write-Status "PROGRESS: CPU - Could not check CPU usage for process $($proc.ProcessId)"
                                }
                            }
                        } else {
                            Write-Status "PROGRESS: PROCESS CHECK - No robocopy process found for $folderName - job may be hung"
                            $hungJobs++
                        }
                    } catch {
                        Write-Status "PROGRESS: PROCESS CHECK - Error checking robocopy process for $folderName"
                    }
                    
                    # If job has been hanging for too long, force termination
                    if ($jobHangTimes[$jobId].ConsecutiveNoProgress -gt 3) {
                        Write-Status "PROGRESS: HANG DETECTED - Job $jobId ($folderName) appears to be hung - forcing termination"
                        
                        # Force kill the robocopy process
                        try {
                            $jobProcesses = Get-WmiObject Win32_Process | Where-Object { $_.ProcessName -eq "robocopy.exe" -and $_.CommandLine -like "*$folderName*" }
                            foreach ($proc in $jobProcesses) {
                                Write-Status "PROGRESS: KILL - Terminating hung robocopy process PID $($proc.ProcessId) for $folderName"
                                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                            }
                        } catch {
                            Write-Status "PROGRESS: ERROR - Could not kill hung robocopy process for $folderName"
                        }
                        
                        # Stop and remove the job
                        try {
                            Stop-Job -Job $job -ErrorAction SilentlyContinue
                            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                            Write-Status "PROGRESS: HANG - Job $jobId terminated due to hang detection"
                        } catch {
                            Write-Status "PROGRESS: ERROR - Could not stop hung job $jobId"
                        }
                        
                        $completedJobs++
                        $processedJobs += $jobId
                        $progressUpdated = $true
                        continue
                    }
                }
                
                Write-Status "PROGRESS: DEBUG - Job $jobId still running ($([math]::Round($elapsed))s elapsed)"
            }
            elseif ($job.State -eq "Failed") {
                $completedJobs++
                $failedJobs++
                $processedJobs += $jobId
                $progressUpdated = $true
                
                Write-Status "PROGRESS: DEBUG - Job $jobId failed, getting error details..."
                
                # Get failure details
                try {
                    $jobError = $job.ChildJobs[0].JobStateInfo.Reason
                    if ($jobError) {
                        Write-Status "PROGRESS: ERROR $folderName job failed - $($jobError.Message)"
                    } else {
                        Write-Status "PROGRESS: ERROR $folderName job failed - no error details available"
                    }
                } catch {
                    Write-Status "PROGRESS: ERROR $folderName job failed - could not get error details"
                }
                
                try {
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                } catch {
                    # Ignore cleanup errors for failed jobs
                }
            }
            else {
                Write-Status "PROGRESS: DEBUG - Job $jobId in state: $($job.State)"
            }
        }
        
        # Update progress tracking
        if ($progressUpdated) {
            $lastProgressUpdate = Get-Date
        }
        
        # Check for global hang condition
        $globalHangTime = ((Get-Date) - $lastProgressUpdate).TotalSeconds
        if ($globalHangTime -gt 60 -and $runningJobs -gt 0) {
            Write-Status "PROGRESS: GLOBAL HANG - No progress for $([math]::Round($globalHangTime))s with $runningJobs running jobs"
            Write-Status "PROGRESS: GLOBAL HANG - Attempting to recover..."
            
            # Force kill all robocopy processes
            try {
                $allRobocopyProcesses = Get-WmiObject Win32_Process | Where-Object { $_.ProcessName -eq "robocopy.exe" }
                foreach ($proc in $allRobocopyProcesses) {
                    Write-Status "PROGRESS: KILL ALL - Terminating robocopy process PID $($proc.ProcessId)"
                    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Status "PROGRESS: ERROR - Could not kill all robocopy processes"
            }
            
            # Stop all running jobs
            foreach ($jobInfo in $script:parallelJobs) {
                if ($jobInfo.Job.State -eq "Running") {
                    try {
                        Stop-Job -Job $jobInfo.Job -ErrorAction SilentlyContinue
                        Remove-Job -Job $jobInfo.Job -Force -ErrorAction SilentlyContinue
                        Write-Status "PROGRESS: GLOBAL KILL - Terminated job $($jobInfo.JobId) for $($jobInfo.FolderName)"
                    } catch {
                        Write-Status "PROGRESS: ERROR - Could not stop job $($jobInfo.JobId)"
                    }
                }
            }
            
            break
        }
        
        # Update progress
        $progressPercent = [math]::Round(($completedJobs / $totalJobs) * 100)
        Update-Progress $progressPercent
        
        $statusMsg = "PROGRESS: $completedJobs of $totalJobs completed ($runningJobs running, $failedJobs failed"
        if ($hungJobs -gt 0) {
            $statusMsg += ", $hungJobs hung"
        }
        $statusMsg += ") - $progressPercent percent"
        Write-Status $statusMsg
        
        # This is the old blocking version - replaced with timer-based approach
        Write-Status "PROGRESS: Legacy blocking monitoring - this should not be called"
    }
    
    # Clean up any remaining jobs
    Write-Status "PROGRESS: DEBUG - Cleaning up remaining jobs..."
    foreach ($jobInfo in $script:parallelJobs) {
        try {
            if ($jobInfo.Job.State -ne "Completed") {
                Write-Status "PROGRESS: DEBUG - Stopping remaining job $($jobInfo.JobId)"
                Stop-Job -Job $jobInfo.Job -ErrorAction SilentlyContinue
                Remove-Job -Job $jobInfo.Job -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Status "PROGRESS: DEBUG - Error cleaning up remaining job: $($_.Exception.Message)"
        }
    }
    
    Write-Status "PROGRESS: All parallel copy jobs completed"
    Write-Status "PROGRESS: DEBUG - Job monitoring ended at $(Get-Date)"
}

function Initialize-Optimization {
    Write-Status "=== OPTIMIZATION INITIALIZATION ==="
    
    # Detect drive types
    $script:sourceDriveType = Get-DriveType $sourceDir
    $script:destDriveType = Get-DriveType (Split-Path $script:destinationDir -Parent)
    
    Write-Status "OPTIMIZATION: Source drive type: $($script:sourceDriveType)"
    Write-Status "OPTIMIZATION: Destination drive type: $($script:destDriveType)"
    
    # Get optimal parameters
    $optimization = Get-OptimalRobocopyParams $script:sourceDriveType $script:destDriveType
    $script:optimalThreads = $optimization.Threads
    $script:optimalParams = $optimization.Params
    
    Write-Status "OPTIMIZATION: $($optimization.Description)"
    Write-Status "OPTIMIZATION: Using $($script:optimalThreads) threads"
    Write-Status "OPTIMIZATION: Parameters: $($script:optimalParams)"
    
    # Initialize copy statistics (StartTime already set in OnCopyClick)
    $script:copyStats.CopiedFiles = 0
    $script:copyStats.CopiedSize = 0
    
    Write-Status "=== OPTIMIZATION READY ==="
}

function Write-Status {
    param([string]$message)
    if ($script:statusTextBox) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $prefixedMessage = "[$timestamp] $message"
        $script:statusTextBox.AppendText("$prefixedMessage`r`n")
        $script:statusTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Write-OperationStart {
    param(
        [int]$totalFiles,
        [long]$totalSize,
        [string]$sourceDir,
        [string]$destDir,
        [string]$operation = "copy"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $sizeStr = Format-FileSize $totalSize
    $message = "[$timestamp] Starting $operation - $totalFiles files ($sizeStr) from $sourceDir to $destDir"
    
    if ($script:statusTextBox) {
        $script:statusTextBox.AppendText("$message`r`n")
        $script:statusTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    # Accumulate grand totals for final session summary
    $script:totalOperationFiles += $totalFiles
    $script:totalOperationSize += $totalSize
}

function Write-CleanProgress {
    param(
        [string]$currentFile,
        [long]$fileSize,
        [int]$percent,
        [int]$currentFileNum = 0,
        [int]$totalFiles = 0
    )
    
    # Only log if percent changed by at least 5% or if it's a different file
    if (($percent - $script:lastLoggedPercent) -ge 5 -or $currentFile -ne $script:lastLoggedFile) {
        $script:lastLoggedPercent = $percent
        $script:lastLoggedFile = $currentFile
        
        $timestamp = Get-Date -Format "HH:mm:ss"
        $sizeStr = Format-FileSize $fileSize
        
        # Format progress percentage with consistent width
        $percentStr = "{0,3}" -f $percent
        
        if ($fileSize -le 0) {
            $message = "[$timestamp] Copying ($percentStr%) - $currentFile"
        } else {
            $message = "[$timestamp] Copying ($percentStr%) - $currentFile ($sizeStr)"
        }
        
        if ($script:statusTextBox) {
            $script:statusTextBox.AppendText("$message`r`n")
            $script:statusTextBox.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

function Write-CopyError {
    param(
        [string]$filePath,
        [string]$errorDescription,
        [string]$action = "skipped"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $fileName = Split-Path $filePath -Leaf
    $message = "[$timestamp] ERROR - Failed to copy $fileName ($errorDescription) - $action"
    
    if ($script:statusTextBox) {
        $script:statusTextBox.AppendText("$message`r`n")
        $script:statusTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Write-CleanSummary {
    param(
        [int]$totalFiles,
        [long]$totalSize,
        [string]$operation = "Copy complete"
    )
    
    if ($script:copyStats.StartTime) {
        $elapsed = ((Get-Date) - $script:copyStats.StartTime)
        $hours = [int][math]::Floor($elapsed.TotalHours)
        $minutes = [int]$elapsed.Minutes
        $seconds = [int]$elapsed.Seconds
        $elapsedStr = "{0:D2}h{1:D2}m{2:D2}s" -f $hours, $minutes, $seconds
        $sizeStr = Format-FileSize $totalSize
        
        $timestamp = Get-Date -Format "HH:mm:ss"
        $message = "[$timestamp] $operation - $totalFiles files, $sizeStr, $elapsedStr elapsed"
        
        if ($script:statusTextBox) {
            $script:statusTextBox.AppendText("$message`r`n")
            $script:statusTextBox.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

function Format-FileSize {
    param([long]$bytes)
    
    if ($bytes -ge 1GB) {
        return "$([math]::Round($bytes / 1GB, 2)) GB"
    } elseif ($bytes -ge 1MB) {
        return "$([math]::Round($bytes / 1MB, 1)) MB"
    } elseif ($bytes -ge 1KB) {
        return "$([math]::Round($bytes / 1KB, 0)) KB"
    } else {
        return "$bytes B"
    }
}

function Update-Progress {
    param([int]$value)
    if ($script:progressBar) {
        $script:progressBar.Value = [Math]::Min($value, 100)
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# Global progress tracking system
$script:globalProgress = @{
    TotalOperations = 0
    CompletedOperations = 0
    TotalFiles = 0
    CompletedFiles = 0
    TotalSize = 0
    CompletedSize = 0
    CurrentOperation = ""
    StartTime = $null
    OperationDetails = @()
}

function Initialize-GlobalProgress {
    param(
        [int]$totalOperations,
        [int]$totalFiles,
        [long]$totalSize,
        [string]$operationName
    )
    
    $script:globalProgress.TotalOperations = $totalOperations
    $script:globalProgress.CompletedOperations = 0
    $script:globalProgress.TotalFiles = $totalFiles
    $script:globalProgress.CompletedFiles = 0
    $script:globalProgress.TotalSize = $totalSize
    $script:globalProgress.CompletedSize = 0
    $script:globalProgress.CurrentOperation = $operationName
    $script:globalProgress.StartTime = Get-Date
    $script:globalProgress.OperationDetails = @()
    $script:lastReportedProgress = 0
    
    Write-Status "PROGRESS: Initialized - $totalOperations operations, $totalFiles files, $([math]::Round($totalSize/1GB, 2)) GB"
    Update-AccurateProgress
}

function Update-OperationProgress {
    param(
        [string]$operationName,
        [int]$completedFiles = 0,
        [long]$completedSize = 0,
        [int]$totalFiles = 0,
        [long]$totalSize = 0,
        [double]$percentComplete = -1
    )
    
    # Update current operation
    $script:globalProgress.CurrentOperation = $operationName
    
    # If specific progress is provided, calculate based on that
    if ($percentComplete -ge 0) {
        # Use provided percentage for this operation
        $operationFiles = if ($totalFiles -gt 0) { [math]::Round($totalFiles * ($percentComplete / 100)) } else { 0 }
        $operationSize = if ($totalSize -gt 0) { [math]::Round($totalSize * ($percentComplete / 100)) } else { 0 }
        
        $script:globalProgress.CompletedFiles = $script:globalProgress.CompletedFiles + $operationFiles
        $script:globalProgress.CompletedSize = $script:globalProgress.CompletedSize + $operationSize
    } else {
        # Use actual completed counts
        $script:globalProgress.CompletedFiles += $completedFiles
        $script:globalProgress.CompletedSize += $completedSize
    }
    
    Update-AccurateProgress
}

function Complete-Operation {
    param(
        [string]$operationName,
        [int]$totalFiles = 0,
        [long]$totalSize = 0
    )
    
    $script:globalProgress.CompletedOperations++
    $script:globalProgress.CompletedFiles += $totalFiles
    $script:globalProgress.CompletedSize += $totalSize
    
    # Store operation details
    $script:globalProgress.OperationDetails += @{
        Name = $operationName
        Files = $totalFiles
        Size = $totalSize
        CompletedAt = Get-Date
    }
    
    Write-Status "PROGRESS: Completed '$operationName' - $totalFiles files, $([math]::Round($totalSize/1MB, 1)) MB"
    Update-AccurateProgress
}

function Test-OverwriteRisk {
    param(
        [string]$sourceFolder,
        [string]$destinationBase,
        [string]$folderName
    )
    
    $destinationPath = Join-Path $destinationBase $folderName
    $overwriteFiles = @()
    
    if (Test-Path $destinationPath) {
        try {
            # Get all files that would be overwritten
            $sourceFiles = Get-ChildItem -Path $sourceFolder -Recurse -File -ErrorAction SilentlyContinue
            foreach ($sourceFile in $sourceFiles) {
                $relativePath = $sourceFile.FullName.Substring($sourceFolder.Length + 1)
                $destFile = Join-Path $destinationPath $relativePath
                
                if (Test-Path $destFile) {
                    $destFileInfo = Get-Item $destFile
                    $overwriteFiles += [PSCustomObject]@{
                        RelativePath = $relativePath
                        SourceSize = $sourceFile.Length
                        DestSize = $destFileInfo.Length
                        DestModified = $destFileInfo.LastWriteTime
                    }
                }
            }
        } catch {
            Write-Status "WARNING: Could not fully analyze overwrite risk for '$folderName': $($_.Exception.Message)"
        }
    }
    
    return $overwriteFiles
}

function Show-SkippedFilesInfo {
    param(
        [array]$skippedFiles,
        [string]$folderName
    )
    
    if ($skippedFiles.Count -eq 0) {
        return  # No skipped files, nothing to show
    }
    
    # Create informational dialog
    $infoForm = New-Object System.Windows.Forms.Form
    $infoForm.Text = "Files Will Be Skipped - CopyAmigo v10.0"
    $infoForm.Size = New-Object System.Drawing.Size(600, 500)
    $infoForm.StartPosition = "CenterParent"
    $infoForm.FormBorderStyle = "FixedDialog"
    $infoForm.MaximizeBox = $false
    $infoForm.MinimizeBox = $false
    $infoForm.TopMost = $true
    
    # Info icon and message
    $iconLabel = New-Object System.Windows.Forms.Label
    $iconLabel.Text = "Info"
    $iconLabel.Font = New-Object System.Drawing.Font("Segoe UI", 24)
    $iconLabel.Location = New-Object System.Drawing.Point(20, 20)
    $iconLabel.Size = New-Object System.Drawing.Size(50, 50)
    $infoForm.Controls.Add($iconLabel)
    
    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Text = "Files will be skipped in '$folderName'"
    $messageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $messageLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    $messageLabel.Location = New-Object System.Drawing.Point(80, 20)
    $messageLabel.Size = New-Object System.Drawing.Size(500, 30)
    $infoForm.Controls.Add($messageLabel)
    
    $detailLabel = New-Object System.Windows.Forms.Label
    $detailLabel.Text = "The following $($skippedFiles.Count) file(s) already exist and will be skipped (not overwritten):"
    $detailLabel.Location = New-Object System.Drawing.Point(20, 60)
    $detailLabel.Size = New-Object System.Drawing.Size(550, 20)
    $infoForm.Controls.Add($detailLabel)
    
    # File list
    $fileListBox = New-Object System.Windows.Forms.ListBox
    $fileListBox.Location = New-Object System.Drawing.Point(20, 90)
    $fileListBox.Size = New-Object System.Drawing.Size(550, 280)
    $fileListBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    
    foreach ($file in $skippedFiles | Select-Object -First 50) {  # Limit to first 50 for performance
        $sizeInfo = "$(Format-FileSize $file.SourceSize) -> $(Format-FileSize $file.DestSize)"
        $dateInfo = $file.DestModified.ToString("yyyy-MM-dd HH:mm")
        $itemText = "$($file.RelativePath) ($sizeInfo, dest modified: $dateInfo)"
        $fileListBox.Items.Add($itemText)
    }
    
    if ($skippedFiles.Count -gt 50) {
        $fileListBox.Items.Add("... and $($skippedFiles.Count - 50) more files")
    }
    
    $infoForm.Controls.Add($fileListBox)
    
    # OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK - Continue Copy"
    $okButton.Location = New-Object System.Drawing.Point(400, 390)
    $okButton.Size = New-Object System.Drawing.Size(150, 35)
    $okButton.BackColor = [System.Drawing.Color]::DarkBlue
    $okButton.ForeColor = [System.Drawing.Color]::White
    $okButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $infoForm.Controls.Add($okButton)
    
    # Safety message
    $safetyLabel = New-Object System.Windows.Forms.Label
    $safetyLabel.Text = "✅ Your existing files are safe - they will not be modified or replaced."
    $safetyLabel.ForeColor = [System.Drawing.Color]::DarkGreen
    $safetyLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $safetyLabel.Location = New-Object System.Drawing.Point(20, 440)
    $safetyLabel.Size = New-Object System.Drawing.Size(550, 20)
    $infoForm.Controls.Add($safetyLabel)
    
    # Show dialog
    $result = $infoForm.ShowDialog()
    $infoForm.Dispose()
}

# (removed duplicate) — use the earlier Format-FileSize implementation

function Update-AccurateProgress {
    if (-not $script:globalProgress.TotalFiles -or -not $script:globalProgress.TotalSize) {
        return
    }
    
    # Track last reported progress to avoid spam
    if (-not $script:lastReportedProgress) {
        $script:lastReportedProgress = 0
    }
    
    # Calculate progress based on both file count and size
    $fileProgress = if ($script:globalProgress.TotalFiles -gt 0) {
        ($script:globalProgress.CompletedFiles / $script:globalProgress.TotalFiles) * 100
    } else { 0 }
    
    $sizeProgress = if ($script:globalProgress.TotalSize -gt 0) {
        ($script:globalProgress.CompletedSize / $script:globalProgress.TotalSize) * 100
    } else { 0 }
    
    $operationProgress = if ($script:globalProgress.TotalOperations -gt 0) {
        ($script:globalProgress.CompletedOperations / $script:globalProgress.TotalOperations) * 100
    } else { 0 }
    
    # Use weighted average (size is most important, then files, then operations)
    $overallProgress = [math]::Round(($sizeProgress * 0.6) + ($fileProgress * 0.3) + ($operationProgress * 0.1), 1)
    $overallProgress = [math]::Min($overallProgress, 100)
    
    # Only show progress updates every 5% or when operation completes
    $progressDifference = $overallProgress - $script:lastReportedProgress
    $shouldUpdate = ($progressDifference -ge 5) -or ($overallProgress -eq 100) -or ($script:lastReportedProgress -eq 0)
    
    if (-not $shouldUpdate) {
        return
    }
    
    $script:lastReportedProgress = $overallProgress
    
    # Update progress bar
    Update-Progress ([int]$overallProgress)
    
    # Calculate transfer rate and ETA
    $elapsed = ((Get-Date) - $script:globalProgress.StartTime).TotalSeconds
    $transferRate = if ($elapsed -gt 0) { $script:globalProgress.CompletedSize / $elapsed } else { 0 }
    
    $remainingSize = $script:globalProgress.TotalSize - $script:globalProgress.CompletedSize
    $eta = if ($transferRate -gt 0) {
        $remainingSeconds = $remainingSize / $transferRate
        $minutes = [math]::Floor($remainingSeconds / 60)
        $seconds = [math]::Floor($remainingSeconds % 60)
        "${minutes}m ${seconds}s"
    } else {
        "Calculating..."
    }
    
    $transferRateMB = [math]::Round($transferRate / 1MB, 1)
    
    # Update status
    $statusMsg = "PROGRESS: $overallProgress% complete"
    $statusMsg += " | Files: $($script:globalProgress.CompletedFiles)/$($script:globalProgress.TotalFiles)"
    $statusMsg += " | Size: $([math]::Round($script:globalProgress.CompletedSize/1GB, 2))/$([math]::Round($script:globalProgress.TotalSize/1GB, 2)) GB"
    $statusMsg += " | Speed: ${transferRateMB} MB/s"
    $statusMsg += " | ETA: $eta"
    
    if ($script:globalProgress.CurrentOperation) {
        $statusMsg += " | Current: $($script:globalProgress.CurrentOperation)"
    }
    
    Write-Status $statusMsg
}

function Stop-AllProcesses {
    # Stop monitoring timer if it exists
    if ($script:monitoringTimer) {
        Write-Status "STOP: Stopping monitoring timer..."
        try {
            $script:monitoringTimer.Stop()
            $script:monitoringTimer.Dispose()
            Write-Status "STOP: Monitoring timer stopped"
        } catch {
            Write-Status "STOP: Error stopping monitoring timer - $($_.Exception.Message)"
        }
        $script:monitoringTimer = $null
    }
    
    # Clean up any running robocopy processes
    if ($script:activeProcesses.Count -gt 0) {
        Write-Status "Cleaning up active processes..."
        foreach ($process in $script:activeProcesses) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                    $process.WaitForExit(5000)  # Wait up to 5 seconds
                }
                $process.Dispose()
            } catch {
                Write-Status "Warning: Could not clean up process - $($_.Exception.Message)"
            }
        }
        $script:activeProcesses = @()
    }
}



function Copy-FolderWithRobocopy {
    param(
        [string]$source,
        [string]$destination,
        [string]$folderName
    )
    
    Write-Status "=== ROBOCOPY DEBUG START for $folderName ==="
    Write-Status "DEBUG: Source: '$source'"
    Write-Status "DEBUG: Destination: '$destination'"
    Write-Status "DEBUG: Folder Name: '$folderName'"
    
    if ($script:cancelRequested) {
        Write-Status "Copy cancelled: Skipping $folderName"
        return $false
    }
    
    if (Test-Path $source) {
        Write-Status "DEBUG: Source path exists"
        
        # Test basic permissions by trying to list directory contents
        try {
            Write-Status "DEBUG: Testing source directory access..."
            $testItems = Get-ChildItem $source -ErrorAction Stop
            Write-Status "DEBUG: Successfully read source directory - $($testItems.Count) items found"
        } catch {
            Write-Status "DEBUG: ERROR accessing source directory: $($_.Exception.Message)"
            Write-Status "ERROR: Cannot access source directory - check permissions"
            Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
            return $false
        }
        
        # Test destination directory creation
        try {
            $destParent = Split-Path $destination -Parent
            if (-not (Test-Path $destParent)) {
                Write-Status "DEBUG: Creating destination parent directory: $destParent"
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                Write-Status "DEBUG: Successfully created destination parent"
            } else {
                Write-Status "DEBUG: Destination parent already exists: $destParent"
            }
        } catch {
            Write-Status "DEBUG: ERROR creating destination directory: $($_.Exception.Message)"
            Write-Status "ERROR: Cannot create destination directory - check permissions"
            Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
            return $false
        }
        
        Write-Status "Copying $folderName..."
        
        # Start robocopy process with proper cleanup
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "robocopy"
        # Use multithreading for better performance
        $processInfo.Arguments = "`"$source`" `"$destination`" /E /MT:32 /R:1 /W:1 /NP /NDL /NC /XO"
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        
        Write-Status "DEBUG: Robocopy command: robocopy $($processInfo.Arguments)"
        Write-Status "DEBUG: Parameters explained: /E=copy subdirs, /MT:32=32 threads, /R:1=retry once, /W:1=wait 1sec, /NP=no progress, /NDL=no directory list, /NC=no class, /XO=exclude older (overwrite with newer files)"
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        
        try {
            Write-Status "DEBUG: Starting robocopy process..."
            $process.Start() | Out-Null
            $script:activeProcesses += $process
            
            Write-Status "DEBUG: Process started with ID: $($process.Id)"
            
            # Wait for completion with cancellation check and timeout
            $waitCount = 0
            $timeoutCount = 600  # 60 seconds timeout (600 * 100ms)
            while (-not $process.HasExited -and -not $script:cancelRequested -and $waitCount -lt $timeoutCount) {
                Start-Sleep -Milliseconds 100
                $waitCount++
                if ($waitCount % 50 -eq 0) {  # Every 5 seconds
                    $elapsedMs = $waitCount * 100
                    $statusText = "DEBUG: Still waiting for robocopy... ($elapsedMs ms elapsed)"
                    Write-Status $statusText
                }
                [System.Windows.Forms.Application]::DoEvents()
            }
            
            # Check if we timed out
            if ($waitCount -ge $timeoutCount -and -not $process.HasExited) {
                Write-Status "DEBUG: ROBOCOPY TIMEOUT! Process has been running for over 60 seconds"
                Write-Status "DEBUG: Attempting to kill hanging robocopy process..."
                try {
                    $process.Kill()
                    $process.WaitForExit(5000)
                    Write-Status "DEBUG: Successfully killed hanging robocopy process"
                } catch {
                    Write-Status "DEBUG: Error killing robocopy process: $($_.Exception.Message)"
                }
                
                Write-Status "ERROR: Robocopy process timed out - trying PowerShell native copy as fallback"
                
                # Try PowerShell native copy as fallback
                try {
                    Write-Status "DEBUG: Attempting PowerShell Copy-Item fallback..."
                    
                    # Ensure destination parent exists
                    $destParent = Split-Path $destination -Parent
                    if (-not (Test-Path $destParent)) {
                        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                        Write-Status "DEBUG: Created destination parent directory"
                    }
                    
                    # Use PowerShell Copy-Item
                    Copy-Item -Path $source -Destination $destination -Recurse -Force
                    Write-Status "DEBUG: PowerShell copy completed successfully"
                    Write-Status "$folderName copied successfully (using PowerShell fallback)"
                    Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
                    return $true
                    
                } catch {
                    Write-Status "DEBUG: PowerShell copy also failed: $($_.Exception.Message)"
                    Write-Status "ERROR: Both robocopy and PowerShell copy failed"
                    Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
                    return $false
                }
            }
            
            if ($script:cancelRequested) {
                Write-Status "Cancelling $folderName copy..."
                try {
                    $process.Kill()
                    $process.WaitForExit(2000)
                } catch {
                    Write-Status "Warning: Could not stop robocopy process cleanly"
                }
                return $false
            }
            
            # Wait for complete finish
            Write-Status "DEBUG: Waiting for process to complete..."
            $process.WaitForExit()
            
            # Get output
            $output = ""
            $errorOutput = ""
            try {
                $output = $process.StandardOutput.ReadToEnd()
                $errorOutput = $process.StandardError.ReadToEnd()
            } catch {
                Write-Status "DEBUG: Could not read process output: $($_.Exception.Message)"
            }
            
            Write-Status "DEBUG: Process completed with exit code: $($process.ExitCode)"
            
            if ($output -and $output.Trim().Length -gt 0) {
                Write-Status "DEBUG: Robocopy output (first 500 chars): $($output.Substring(0, [Math]::Min(500, $output.Length)))"
            }
            
            if ($errorOutput -and $errorOutput.Trim().Length -gt 0) {
                Write-Status "DEBUG: Robocopy error output: $errorOutput"
            }
            
            # Check exit code (robocopy uses nonstandard codes)
            $code = $process.ExitCode
            if ($code -le 3) {
                Write-Status "$folderName copied successfully"
                Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
                return $true
            } elseif ($code -lt 8) {
                Write-Status "Warning: $folderName completed with warnings (code $code)"
                Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
                return $true
            } else {
                Write-Status "ERROR: $folderName copy failed (code $code)"
                Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
                return $false
            }
            
        } catch {
            Write-Status "DEBUG: Exception during robocopy process: $($_.Exception.Message)"
            Write-Status "DEBUG: Exception type: $($_.Exception.GetType().Name)"
            Write-Status "Error copying $folderName - $($_.Exception.Message)"
            Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
            return $false
        } finally {
            # Proper cleanup
            try {
                if ($process -and -not $process.HasExited) {
                    $process.Kill()
                    $process.WaitForExit(2000)
                }
                $process.Dispose()
                $script:activeProcesses = $script:activeProcesses | Where-Object { $_ -ne $process }
            } catch {
                Write-Status "Warning: Process cleanup issue - $($_.Exception.Message)"
            }
        }
    } else {
        Write-Status "DEBUG: Source path does not exist: '$source'"
        Write-Status "Skipped: $folderName (not found)"
        Write-Status "=== ROBOCOPY DEBUG END for $folderName ==="
        return $false
    }
}

function Initialize-DestinationFolder {
    Write-Status "Initializing destination folder..."
    Write-Status "Source: $sourceDir"
    Write-Status "Destination: $script:destinationDir"
    
    if (Test-Path $script:destinationDir) {
        Write-Status "Destination folder exists: $script:destinationDir"
    } else {
        Write-Status "Creating destination folder: $script:destinationDir"
        try {
            New-Item -ItemType Directory -Path $script:destinationDir -Force | Out-Null
            Write-Status "Destination folder created successfully"
        } catch {
            Write-Status "Error creating destination folder: $($_.Exception.Message)"
            throw
        }
    }
    Update-Progress 10
}





function Copy-FolderWithOptimization {
    param(
        [string]$source,
        [string]$destination,
        [string]$folderName
    )
    
    Write-Status "=== OPTIMIZED COPY START for $folderName ==="
    
    if ($script:cancelRequested) {
        Write-Status "OPTIMIZED: Copy cancelled: Skipping $folderName"
        return $false
    }
    
    if (Test-Path $source) {
        Write-Status "OPTIMIZED: Starting optimized copy of $folderName..."
        
        # Ensure destination parent exists
        $destParent = Split-Path $destination -Parent
        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }
        
        # Create optimized robocopy process
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "robocopy"
        $processInfo.Arguments = "`"$source`" `"$destination`" $($script:optimalParams)"
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        
        Write-Status "OPTIMIZED: Command: robocopy $($processInfo.Arguments)"
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        
        try {
            $startTime = Get-Date
            Write-Status "OPTIMIZED: [DEBUG] About to start robocopy process for $folderName"
            $process.Start() | Out-Null
            Write-Status "OPTIMIZED: [DEBUG] robocopy process started for $folderName. PID: $($process.Id)"
            $script:activeProcesses += $process
            
            # Real-time progress monitoring
            $progressCount = 0
            $lastProgressUpdate = Get-Date
            $lastUserUpdate = Get-Date
            
            while (-not $process.HasExited -and -not $script:cancelRequested) {
                Start-Sleep -Milliseconds 200
                
                # Update progress every 2 seconds
                if (((Get-Date) - $lastProgressUpdate).TotalSeconds -ge 2) {
                    $elapsed = ((Get-Date) - $startTime).TotalSeconds
                    Write-Status "OPTIMIZED: $folderName copying... (${elapsed}s elapsed)"
                    $lastProgressUpdate = Get-Date
                }
                # User-facing update every 6 seconds
                if (((Get-Date) - $lastUserUpdate).TotalSeconds -ge 6) {
                    $elapsed = ((Get-Date) - $startTime).TotalSeconds
                    Write-Status "[USER] Still copying $folderName... ${elapsed}s elapsed. UI is responsive."
                    Write-Status "OPTIMIZED: [DEBUG] Calling DoEvents for UI responsiveness."
                    [System.Windows.Forms.Application]::DoEvents()
                    Write-Status "OPTIMIZED: [DEBUG] DoEvents call completed."
                    $lastUserUpdate = Get-Date
                }
                Write-Status "OPTIMIZED: [DEBUG] Calling DoEvents inside main loop."
                [System.Windows.Forms.Application]::DoEvents()
                Write-Status "OPTIMIZED: [DEBUG] DoEvents call completed inside main loop."
            }
            Write-Status "OPTIMIZED: [DEBUG] Exited main copy loop. About to call WaitForExit."
            $process.WaitForExit()
            Write-Status "OPTIMIZED: [DEBUG] WaitForExit completed. Process exited: $($process.HasExited)"
            
            # Get results
            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()
            $exitCode = $process.ExitCode
            
            $totalTime = ((Get-Date) - $startTime).TotalSeconds
            
            Write-Status "OPTIMIZED: $folderName completed in $totalTime seconds"
            Write-Status "OPTIMIZED: Exit code: $exitCode"
            
            if ($exitCode -le 3) {
                Write-Status "OPTIMIZED: [OK] $folderName copied successfully"
                return $true
            } elseif ($exitCode -lt 8) {
                Write-Status "OPTIMIZED: [WARNING] $folderName completed with warnings (code: $exitCode)"
                if ($errorOutput) { Write-Status "OPTIMIZED: Error details: $errorOutput" }
                return $true
            } else {
                Write-Status "OPTIMIZED: [ERROR] $folderName copy failed (code: $exitCode)"
                if ($errorOutput) { Write-Status "OPTIMIZED: Error details: $errorOutput" }
                return $false
            }
            
        } catch {
            Write-Status "OPTIMIZED: Error copying $folderName - $($_.Exception.Message)"
            return $false
        } finally {
            if ($process -and -not $process.HasExited) {
                $process.Kill()
                $process.WaitForExit(2000)
            }
            $process.Dispose()
            $script:activeProcesses = $script:activeProcesses | Where-Object { $_ -ne $process }
        }
    } else {
        Write-Status "OPTIMIZED: Source not found: $source"
        return $false
    }
}

function Get-TscanMainFolders {
    $tscanPath = Join-Path $sourceDir "Tscan"
    
    if (-not (Test-Path $tscanPath -PathType Container)) {
        return @()
    }
    
    $validMainFolders = @()
    $subfolders = Get-ChildItem $tscanPath -Directory -ErrorAction SilentlyContinue
    
    foreach ($subfolder in $subfolders) {
        if ($subfolder.Name -eq "DGN" -or $subfolder.Name -eq "Settings") {
            continue
        }
        
        $mainFolderPath = Join-Path $tscanPath $subfolder.Name
        $laser02GroundPath = Join-Path $mainFolderPath "Laser02 - Ground by line"
        
        if (Test-Path $laser02GroundPath -PathType Container) {
            $laser02Files = Get-ChildItem $laser02GroundPath -File -ErrorAction SilentlyContinue
            if ($laser02Files -and $laser02Files.Count -gt 0) {
                $validMainFolders += $subfolder.Name
            }
        }
    }
    
    return $validMainFolders | Sort-Object
}

function Get-TerrascanTscanSubfolders {
    param([string]$sourcePath = $script:sourceDir)
    
    try {
        $tscanPath = Join-Path $sourcePath "Tscan"
        if (-not (Test-Path $tscanPath -PathType Container)) {
            # Removed Write-Host to prevent popups in executable
            return @()
        }
        
        $subfolders = @()
        $tscanItems = Get-ChildItem $tscanPath -Directory | Where-Object { 
            $_.Name -notin @("DGN", "Settings") -and -not $_.Name.StartsWith("~") -and -not $_.Name.StartsWith(".")
        }
        
        foreach ($item in $tscanItems) {
            # Check if the folder contains any files or subdirectories
            $hasContent = Get-ChildItem $item.FullName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hasContent) {
                $subfolders += $item.Name
            }
        }
        
        return $subfolders
    } catch {
        # Removed Write-Host to prevent popups in executable
        return @()
    }
}

function Get-TscanSubfolders {
    param([string]$MainFolderName)
    
    $mainFolderPath = Join-Path $sourceDir "Tscan\$MainFolderName"
    
    if (-not (Test-Path $mainFolderPath -PathType Container)) {
        return @()
    }
    
    $validSubfolders = @()
    $subfolders = Get-ChildItem $mainFolderPath -Directory -ErrorAction SilentlyContinue
    
    foreach ($subfolder in $subfolders) {
        if ($subfolder.Name -notmatch "^(Settings|DGN)$") {
            $validSubfolders += $subfolder.Name
        }
    }
    
    return $validSubfolders | Sort-Object
}

function Copy-FolderSkeleton {
    param(
        [string]$sourceDir,
        [string]$destDir
    )
    if (-not (Test-Path $sourceDir)) { return }
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    # Use robocopy to replicate directory structure only (no files)
    robocopy $sourceDir $destDir /E /XF * /NFL /NDL /NJH /NJS /NC /NS | Out-Null
}

function Copy-TscanData {
    Write-Status "=== TSCAN DATA COPY ==="
    Write-Status "TSCAN: Copies Control, Planning (Boundary & Work Orders), Tscan/DGN, Tscan/Settings, plus user-selected Tscan subfolders and Macro/trj if they exist"

    # System Capabilities Analysis for Tscan
    Write-Status "TSCAN: Analyzing system capabilities for optimal performance..."
    $systemAnalysis = Analyze-SystemCapabilities -sourcePath $sourceDir -destPath $script:destinationDir
    
    # Override the script's optimal parameters with our analysis
    $script:optimalParams = $systemAnalysis.OptimalParams
    Write-Status "TSCAN: Optimized for $($systemAnalysis.RecommendedStrategy) - $($systemAnalysis.OptimalThreads) threads"

    $overallSuccess = $true

    # Step 1: Copy standard project folders for Tscan workflow (always copied)
    Write-Status "TSCAN: Copying standard project folders..."
    $standardFolders = @(
        "Control",
        "Planning\Boundary",
        "Planning\Work Orders",
        "Tscan\DGN",
        "Tscan\Settings"
    )
    
    # Check for existing files that will be skipped
    Write-Status "TSCAN: Checking for existing files that will be skipped..."
    $totalSkippedFiles = 0
    $skippedDetails = @()
    
    foreach ($folder in $standardFolders) {
        $sourcePath = Join-Path $sourceDir $folder
        if (Test-Path $sourcePath) {
            $skippedFiles = Test-OverwriteRisk -sourceFolder $sourcePath -destinationBase $script:destinationDir -folderName $folder
            if ($skippedFiles.Count -gt 0) {
                $totalSkippedFiles += $skippedFiles.Count
                $skippedDetails += [PSCustomObject]@{
                    FolderName = $folder
                    SkippedFiles = $skippedFiles
                }
                Write-Status "TSCAN: Found $($skippedFiles.Count) existing files in '$folder' - these will be skipped (not overwritten)"
            }
        }
    }
    
    # Check for existing files in user-selected Tscan subfolders
    Write-Status "TSCAN: Checking selected Tscan subfolders for existing files..."
    foreach ($selectedFolder in $script:selectedSubfolders) {
        $sourcePath = Join-Path $sourceDir "Tscan\$($script:selectedMainFolder)\$selectedFolder"
        $folderName = "Tscan\$($script:selectedMainFolder)\$selectedFolder"
        if (Test-Path $sourcePath) {
            $skippedFiles = Test-OverwriteRisk -sourceFolder $sourcePath -destinationBase $script:destinationDir -folderName $folderName
            if ($skippedFiles.Count -gt 0) {
                $totalSkippedFiles += $skippedFiles.Count
                $skippedDetails += [PSCustomObject]@{
                    FolderName = $folderName
                    SkippedFiles = $skippedFiles
                }
                Write-Status "TSCAN: Found $($skippedFiles.Count) existing files in '$folderName' - these will be skipped (not overwritten)"
            }
        }
    }
    
    # Show skipped files info if any exist
    if ($totalSkippedFiles -gt 0) {
        Write-Status "TSCAN: INFO - $totalSkippedFiles total files will be skipped to preserve existing data"
    } else {
        Write-Status "TSCAN: No existing files detected - all files will be copied"
    }
    
    $standardSuccessCount = 0
    foreach ($folder in $standardFolders) {
        if ($script:cancelRequested) {
            Write-Status "TSCAN: Operation cancelled by user"
            return $false
        }
        
        $sourcePath = Join-Path $sourceDir $folder
        $destPath = Join-Path $script:destinationDir $folder
        
        if (Test-Path $sourcePath -PathType Container) {
            Write-Status "TSCAN: Copying '$folder'..."
            
            if ($script:useWindowsProgressDialog) {
                Initialize-WindowsProgressDialog -title "CopyAmigo - Tscan" -description "Copying: $folder"
            }
            
            $success = Start-WindowsStyleCopy -sourcePath $sourcePath -destPath $destPath -folderName $folder -operation "Copying standard folder"
            
            if ($script:useWindowsProgressDialog) {
                Close-WindowsProgressDialog
            }
            
            if ($success) {
                $standardSuccessCount++
                Write-Status "TSCAN: Successfully copied '$folder'"
            } else {
                Write-Status "TSCAN: Failed to copy '$folder'"
                $overallSuccess = $false
            }
        } else {
            Write-Status "TSCAN: Folder '$folder' not found - skipping"
        }
    }
    
    Write-Status "TSCAN: Completed $standardSuccessCount of $($standardFolders.Count) standard folders"

    # Step 2: Copy user-selected Tscan subfolders
    $tscanRoot = Join-Path $sourceDir "Tscan"
    $destRoot = Join-Path $script:destinationDir "Tscan"

    # Determine which main folder is currently selected
    $mainFolder = $null
    if ($script:mainFolderDropdown) {
        $mainFolder = $script:mainFolderDropdown.SelectedItem
    }

    if (-not $mainFolder) {
        Write-Status "TSCAN: No main folder selected - standard folders copied successfully."
        return $standardSuccessCount -gt 0
    }

    # If no sub-folders are selected, just return success for standard folders
    if ($script:selectedSubfolders.Count -eq 0) {
        Write-Status "TSCAN: No sub-folders selected - standard folders copied successfully."
        return $standardSuccessCount -gt 0
    }

    Write-Status "TSCAN: Copying user-selected Tscan subfolders from $mainFolder..."

    # Ensure the destination main folder exists
    $destMainPath = Join-Path $destRoot $mainFolder
    if (-not (Test-Path $destMainPath)) {
        New-Item -ItemType Directory -Path $destMainPath -Force | Out-Null
    }

    # Replicate complete skeleton for the main folder (UAV, etc.)
    $mainFolderSrc = Join-Path $tscanRoot $mainFolder
    Write-Status "TSCAN: Replicating complete folder skeleton for $mainFolder..."
    Copy-FolderSkeleton -sourceDir $mainFolderSrc -destDir $destMainPath

    # Copy only user-selected sub-folders
    Write-Status "TSCAN: Copying selected sub-folders..."
    $userSuccessCount = 0
    foreach ($folder in $script:selectedSubfolders) {
        if ($script:cancelRequested) {
            Write-Status "TSCAN: Operation cancelled by user"
            break
        }
        
        $src = Join-Path (Join-Path $tscanRoot $mainFolder) $folder
        $dst = Join-Path $destMainPath $folder
        
        if ($script:useWindowsProgressDialog) {
            Initialize-WindowsProgressDialog -title "CopyAmigo - Tscan ($mainFolder)" -description "Copying: $folder"
        }
        
        $ok = Start-WindowsStyleCopy -sourcePath $src -destPath $dst -folderName "$mainFolder\$folder" -operation "Copying Tscan folder"
        
        if ($script:useWindowsProgressDialog) {
            Close-WindowsProgressDialog
        }

        if ($ok) { 
            $userSuccessCount++ 
            Write-Status "TSCAN: Successfully copied '$mainFolder\$folder'"
            
            # Check for and copy Macro and trj folders if they exist within this subfolder
            $macroSrc = Join-Path $src "Macro"
            $macroDst = Join-Path $dst "Macro"
            $trjSrc = Join-Path $src "trj"
            $trjDst = Join-Path $dst "trj"
            
            # Copy Macro folder if it exists
            if (Test-Path $macroSrc -PathType Container) {
                Write-Status "TSCAN: Found Macro folder in '$mainFolder\$folder' - copying..."
                $macroOk = Start-WindowsStyleCopy -sourcePath $macroSrc -destPath $macroDst -folderName "$mainFolder\$folder\Macro" -operation "Copying Macro folder"
                if ($macroOk) {
                    Write-Status "TSCAN: Successfully copied Macro folder from '$mainFolder\$folder'"
                } else {
                    Write-Status "TSCAN: Failed to copy Macro folder from '$mainFolder\$folder'"
                }
            }
            
            # Copy trj folder if it exists
            if (Test-Path $trjSrc -PathType Container) {
                Write-Status "TSCAN: Found trj folder in '$mainFolder\$folder' - copying..."
                $trjOk = Start-WindowsStyleCopy -sourcePath $trjSrc -destPath $trjDst -folderName "$mainFolder\$folder\trj" -operation "Copying trj folder"
                if ($trjOk) {
                    Write-Status "TSCAN: Successfully copied trj folder from '$mainFolder\$folder'"
                } else {
                    Write-Status "TSCAN: Failed to copy trj folder from '$mainFolder\$folder'"
                }
            }
        } else {
            Write-Status "TSCAN: Failed to copy '$mainFolder\$folder'"
            $overallSuccess = $false
        }
    }

    Write-Status "TSCAN: Completed $userSuccessCount of $($script:selectedSubfolders.Count) selected folders"
    Write-Status "TSCAN: Total operation: $standardSuccessCount standard + $userSuccessCount selected folders"
    
    return $overallSuccess -and ($standardSuccessCount -gt 0 -or $userSuccessCount -gt 0)
}

function Copy-OrthomosaicData {
    Write-Status "=== ORTHOMOSAIC PROCESSING DATA COPY ==="

    $rawDataPath = Join-Path $sourceDir "Raw Data"
    $destRoot = $script:destinationDir

    if (-not (Test-Path $rawDataPath -PathType Container)) {
        Write-Status "ORTHOMOSAIC: Raw Data folder not found - aborting."
        return $false
    }

    # System Capabilities Analysis for Orthomosaic Processing
    Write-Status "ORTHOMOSAIC: Analyzing system capabilities for optimal performance..."
    $systemAnalysis = Analyze-SystemCapabilities -sourcePath $rawDataPath -destPath $script:destinationDir
    
    # Override the script's optimal parameters with our analysis
    $script:optimalParams = $systemAnalysis.OptimalParams
    Write-Status "ORTHOMOSAIC: Optimized for $($systemAnalysis.RecommendedStrategy) - $($systemAnalysis.OptimalThreads) threads"

    Write-Status "ORTHOMOSAIC: Starting orthomosaic processing workflow..."
    $successCount = 0
    $totalOperations = 4  # cam0, GeoRef, Control, Orthomosaic

    # Copy standard project folders for Orthomosaic workflow
    Write-Status "ORTHOMOSAIC: Copying standard project folders..."
    $orthomosaicStandardFolders = @(
        "Control",
        "Orthomosaic\Finished Ortho Photos"
    )
    
    # Check for existing files that will be skipped in standard folders
    Write-Status "ORTHOMOSAIC: Checking for existing files that will be skipped..."
    $totalSkippedFiles = 0
    $skippedDetails = @()
    
    foreach ($folder in $orthomosaicStandardFolders) {
        $sourcePath = Join-Path $sourceDir $folder
        if (Test-Path $sourcePath) {
            $skippedFiles = Test-OverwriteRisk -sourceFolder $sourcePath -destinationBase $destRoot -folderName $folder
            if ($skippedFiles.Count -gt 0) {
                $totalSkippedFiles += $skippedFiles.Count
                $skippedDetails += [PSCustomObject]@{
                    FolderName = $folder
                    SkippedFiles = $skippedFiles
                }
                Write-Status "ORTHOMOSAIC: Found $($skippedFiles.Count) existing files in '$folder' - these will be skipped (not overwritten)"
            }
        }
    }
    
    # Show skipped files info if any exist
    if ($totalSkippedFiles -gt 0) {
        Write-Status "ORTHOMOSAIC: INFO - $totalSkippedFiles total files will be skipped to preserve existing data"
    } else {
        Write-Status "ORTHOMOSAIC: No existing files detected - all files will be copied"
    }
    
    $standardSuccessCount = 0
    foreach ($folder in $orthomosaicStandardFolders) {
        $sourcePath = Join-Path $sourceDir $folder
        $destPath = Join-Path $destRoot $folder
        
        if (Test-Path $sourcePath) {
            Write-Status "ORTHOMOSAIC: Copying '$folder'..."
            $success = Start-WindowsStyleCopy -sourcePath $sourcePath -destPath $destPath -folderName $folder -operation "Copying standard folder"
            if ($success) {
                $standardSuccessCount++
                Write-Status "ORTHOMOSAIC: Successfully copied '$folder'"
            } else {
                Write-Status "ORTHOMOSAIC: Failed to copy '$folder'"
            }
            Close-WindowsProgressDialog
        } else {
            Write-Status "ORTHOMOSAIC: Folder '$folder' not found - skipping"
        }
    }
    
    Write-Status "ORTHOMOSAIC: Completed $standardSuccessCount standard project folders"

    # 1. Copy Raw Data structure with cam0 contents and empty non-cam0 directories
    Write-Status "ORTHOMOSAIC: Processing Raw Data structure..."
    $rawDataSubfolders = Get-ChildItem $rawDataPath -Directory -ErrorAction SilentlyContinue
    $sourceStructureFolder = $null
    $cam0Found = $false
    
    # Step 1: Primary Check - Look for RECON- folder structure
    Write-Status "ORTHOMOSAIC: Step 1 - Checking for RECON- folder structure..."
    foreach ($subfolder in $rawDataSubfolders) {
        # Check if folder name starts with RECON- (case-sensitive, all caps)
        if ($subfolder.Name -match "^RECON-") {
            $dataPath = Join-Path $subfolder.FullName "data"
            if (Test-Path $dataPath -PathType Container) {
                $cam0Path = Join-Path $dataPath "cam0"
                if (Test-Path $cam0Path -PathType Container) {
                    $sourceStructureFolder = $subfolder
                    $cam0Found = $true
                    Write-Status "ORTHOMOSAIC: Found cam0 in RECON- structure ($($subfolder.Name)/data/cam0) - processing..."
                    break
                }
            }
        }
    }
    
    # Step 2: Fallback Check - Look for date-time pattern structure
    if (-not $cam0Found) {
        Write-Status "ORTHOMOSAIC: Step 2 - Checking for date-time pattern structure..."
        foreach ($subfolder in $rawDataSubfolders) {
            # Check if folder name matches pattern: 8 digits, hyphen, 6 digits
            if ($subfolder.Name -match "^\d{8}-\d{6}$") {
                $cam0Path = Join-Path $subfolder.FullName "cam0"
                if (Test-Path $cam0Path -PathType Container) {
                    $sourceStructureFolder = $subfolder
                    $cam0Found = $true
                    Write-Status "ORTHOMOSAIC: Found cam0 in date-time structure ($($subfolder.Name)/cam0) - processing..."
                    break
                }
            }
        }
    }
    
    if ($cam0Found -and $sourceStructureFolder) {
        Write-Status "ORTHOMOSAIC: Processing Raw Data structure from $($sourceStructureFolder.Name)..."
        
        # Create Raw Data destination
        $rawDataDest = Join-Path $destRoot "Raw Data"
        if (-not (Test-Path $rawDataDest -PathType Container)) {
            New-Item -ItemType Directory -Path $rawDataDest -Force | Out-Null
        }
        
        # Create the source structure folder (UTC timestamp or RECON-)
        $sourceStructureDest = Join-Path $rawDataDest $sourceStructureFolder.Name
        if (-not (Test-Path $sourceStructureDest -PathType Container)) {
            New-Item -ItemType Directory -Path $sourceStructureDest -Force | Out-Null
        }
        
        # Copy cam0 folder with all contents exactly
        if ($sourceStructureFolder.Name -match "^RECON-") {
            # RECON- structure: source/data/cam0 -> dest/Raw Data/RECON-/data/cam0
            $dataDest = Join-Path $sourceStructureDest "data"
            if (-not (Test-Path $dataDest -PathType Container)) {
                New-Item -ItemType Directory -Path $dataDest -Force | Out-Null
            }
            
            $cam0Source = Join-Path $sourceStructureFolder.FullName "data\cam0"
            $cam0Dest = Join-Path $dataDest "cam0"
            
            Write-Status "ORTHOMOSAIC: Copying cam0 folder with all contents from RECON- structure..."
            $success = Start-WindowsStyleCopy -sourcePath $cam0Source -destPath $cam0Dest -folderName "cam0" -operation "Copying cam0 folder with contents"
            if ($success) {
                $successCount++
                Write-Status "ORTHOMOSAIC: Successfully copied cam0 folder with contents from RECON- structure"
            } else {
                Write-Status "ORTHOMOSAIC: Failed to copy cam0 folder from RECON- structure"
            }
            Close-WindowsProgressDialog
            
            # Create all other non-cam0 directories as empty folders
            $sourceDataItems = Get-ChildItem (Join-Path $sourceStructureFolder.FullName "data") -Directory -ErrorAction SilentlyContinue
            foreach ($item in $sourceDataItems) {
                if ($item.Name -ne "cam0") {
                    $emptyDirDest = Join-Path $dataDest $item.Name
                    if (-not (Test-Path $emptyDirDest -PathType Container)) {
                        New-Item -ItemType Directory -Path $emptyDirDest -Force | Out-Null
                        Write-Status "ORTHOMOSAIC: Created empty directory: $($item.Name)"
                    }
                }
            }
            
        } else {
            # UTC timestamp structure: source/cam0 -> dest/Raw Data/UTC/cam0
            $cam0Source = Join-Path $sourceStructureFolder.FullName "cam0"
            $cam0Dest = Join-Path $sourceStructureDest "cam0"
            
            Write-Status "ORTHOMOSAIC: Copying cam0 folder with all contents from UTC timestamp structure..."
            $success = Start-WindowsStyleCopy -sourcePath $cam0Source -destPath $cam0Dest -folderName "cam0" -operation "Copying cam0 folder with contents"
            if ($success) {
                $successCount++
                Write-Status "ORTHOMOSAIC: Successfully copied cam0 folder with contents from UTC timestamp structure"
            } else {
                Write-Status "ORTHOMOSAIC: Failed to copy cam0 folder from UTC timestamp structure"
            }
            Close-WindowsProgressDialog
            
            # Create all other non-cam0 directories as empty folders
            $sourceItems = Get-ChildItem $sourceStructureFolder.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($item in $sourceItems) {
                if ($item.Name -ne "cam0") {
                    $emptyDirDest = Join-Path $sourceStructureDest $item.Name
                    if (-not (Test-Path $emptyDirDest -PathType Container)) {
                        New-Item -ItemType Directory -Path $emptyDirDest -Force | Out-Null
                        Write-Status "ORTHOMOSAIC: Created empty directory: $($item.Name)"
                    }
                }
            }
        }
        
        Write-Status "ORTHOMOSAIC: Successfully processed Raw Data structure with cam0 contents and empty directories"
        
    } else {
        Write-Status "ORTHOMOSAIC: No cam0 folder found in either RECON- or date-time structures"
    }

    # 2. Copy only .dat files from GeoRef folder
    Write-Status "ORTHOMOSAIC: Copying .dat files from GeoRef folder..."
    $geoRefSource = Join-Path $rawDataPath "GeoRef"
    $geoRefDest = Join-Path $destRoot "GeoRef"
    
    if (Test-Path $geoRefSource -PathType Container) {
        # Create destination directory if it doesn't exist
        if (-not (Test-Path $geoRefDest -PathType Container)) {
            New-Item -ItemType Directory -Path $geoRefDest -Force | Out-Null
        }
        
        # Find all .dat files in the GeoRef folder
        $datFiles = Get-ChildItem $geoRefSource -Filter "*.dat" -File -ErrorAction SilentlyContinue
        
        if ($datFiles -and $datFiles.Count -gt 0) {
            Write-Status "ORTHOMOSAIC: Found $($datFiles.Count) .dat files in GeoRef folder"
            
            $copiedCount = 0
            foreach ($file in $datFiles) {
                $destFile = Join-Path $geoRefDest $file.Name
                try {
                    Copy-Item $file.FullName $destFile -Force
                    $copiedCount++
                    Write-Status "ORTHOMOSAIC: Copied $($file.Name)"
                } catch {
                    Write-Status "ORTHOMOSAIC: Failed to copy $($file.Name) - $($_.Exception.Message)"
                }
            }
            
            if ($copiedCount -gt 0) {
                $successCount++ 
                Write-Status "ORTHOMOSAIC: Successfully copied $copiedCount .dat files from GeoRef folder"
            } else {
                Write-Status "ORTHOMOSAIC: No .dat files were successfully copied from GeoRef folder"
            }
        } else {
            Write-Status "ORTHOMOSAIC: No .dat files found in GeoRef folder"
        }
    } else {
        Write-Status "ORTHOMOSAIC: GeoRef folder not found in Raw Data"
    }

    # 3. Copy Control folder (from project root)
    Write-Status "ORTHOMOSAIC: Copying Control folder..."
    $controlSource = Join-Path $sourceDir "Control"
    $controlDest = Join-Path $destRoot "Control"
    
    if (Test-Path $controlSource -PathType Container) {
        $success = Start-WindowsStyleCopy -sourcePath $controlSource -destPath $controlDest -folderName "Control" -operation "Copying Control folder"
        if ($success) { 
            $successCount++ 
            Write-Status "ORTHOMOSAIC: Successfully copied Control folder"
        } else {
            Write-Status "ORTHOMOSAIC: Failed to copy Control folder"
        }
        Close-WindowsProgressDialog
    } else {
        Write-Status "ORTHOMOSAIC: Control folder not found in project root"
    }

    # 4. Copy Orthomosaic folder structure only (from project root)
    Write-Status "ORTHOMOSAIC: Copying Orthomosaic folder structure (skeleton only)..."
    $orthomosaicSource = Join-Path $sourceDir "Orthomosaic"
    $orthomosaicDest = Join-Path $destRoot "Orthomosaic"
    
    if (Test-Path $orthomosaicSource -PathType Container) {
        # Use Copy-FolderSkeleton to only copy folder structure without files
        Write-Status "ORTHOMOSAIC: Replicating Orthomosaic folder skeleton..."
        Copy-FolderSkeleton -sourceDir $orthomosaicSource -destDir $orthomosaicDest
        
        # Check if skeleton was created successfully
        if (Test-Path $orthomosaicDest -PathType Container) {
            $successCount++ 
            Write-Status "ORTHOMOSAIC: Successfully created Orthomosaic folder skeleton"
        } else {
            Write-Status "ORTHOMOSAIC: Failed to create Orthomosaic folder skeleton"
        }
    } else {
        Write-Status "ORTHOMOSAIC: Orthomosaic folder not found in project root"
    }

    Write-Status "ORTHOMOSAIC: Completed $successCount of $totalOperations operations"
    return $successCount -gt 0
}

function Copy-InitialCloudData {
    Write-Status "=== INITIAL CLOUD PROCESSING DATA COPY ==="
    
    $destRoot = $script:destinationDir
    $overallSuccess = $true
    $successCount = 0
    
    # Performance tracking
    $operationStartTime = Get-Date
    $folderTimings = @()
    $totalFilesProcessed = 0
    $totalSizeProcessed = 0
    
    Write-Status "INITIAL CLOUD: Starting system analysis and optimization..."
    
    # Define the folders to copy for Initial Cloud Processing
    $foldersToProcess = @(
        @{
            Name = "Control"
            SourcePath = Join-Path $sourceDir "Control"
            DestPath = Join-Path $destRoot "Control"
            CopyAll = $true
        },
        @{
            Name = "Planning\Boundary"
            SourcePath = Join-Path $sourceDir "Planning\Boundary"
            DestPath = Join-Path $destRoot "Planning\Boundary"
            CopyAll = $true
        },
        @{
            Name = "Planning\Work Orders"
            SourcePath = Join-Path $sourceDir "Planning\Work Orders"
            DestPath = Join-Path $destRoot "Planning\Work Orders"
            CopyAll = $true
        },
        @{
            Name = "Raw Data"
            SourcePath = Join-Path $sourceDir "Raw Data"
            DestPath = Join-Path $destRoot "Raw Data"
            CopyAll = $true
        }
    )
    
    # System Capabilities Analysis
    Write-Status "INITIAL CLOUD: Analyzing system capabilities for optimal performance..."
    $systemAnalysis = Analyze-SystemCapabilities -sourcePath $sourceDir -destPath $destRoot
    
    # Override the script's optimal parameters with our analysis
    $script:optimalParams = $systemAnalysis.OptimalParams
    Write-Status "INITIAL CLOUD: Optimized for $($systemAnalysis.RecommendedStrategy) - $($systemAnalysis.OptimalThreads) threads"
    
    # Pre-analysis: Calculate sizes and file counts for each folder
    Write-Status "INITIAL CLOUD: Analyzing folder sizes and file counts..."
    $analysisStartTime = Get-Date
    
    foreach ($folder in $foldersToProcess) {
        if (Test-Path $folder.SourcePath -PathType Container) {
            $folderAnalysisStart = Get-Date
            Write-Status "INITIAL CLOUD: Analyzing '$($folder.Name)'..."
            
            try {
                # Use -Force to include hidden files for complete analysis
                $items = Get-ChildItem $folder.SourcePath -Recurse -Force -ErrorAction SilentlyContinue
                $getChildItemTime = ((Get-Date) - $folderAnalysisStart).TotalSeconds
                
                $filterStart = Get-Date
                $files = $items | Where-Object { -not $_.PSIsContainer }
                $fileCount = $files.Count
                $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
                $totalSizeGB = [math]::Round($totalSize / 1GB, 3)
                $filterTime = ((Get-Date) - $filterStart).TotalSeconds
                
                $folder.FileCount = $fileCount
                $folder.TotalSize = $totalSize
                $folder.TotalSizeGB = $totalSizeGB
                
                $folderAnalysisTime = ((Get-Date) - $folderAnalysisStart).TotalSeconds
                Write-Status "INITIAL CLOUD: '$($folder.Name)' - $fileCount files, $totalSizeGB GB (analyzed in $([math]::Round($folderAnalysisTime, 2))s)"
                
                $totalFilesProcessed += $fileCount
                $totalSizeProcessed += $totalSize
                
            } catch {
                $folderAnalysisTime = ((Get-Date) - $folderAnalysisStart).TotalSeconds
                Write-Status "INITIAL CLOUD: Error analyzing '$($folder.Name)' after $([math]::Round($folderAnalysisTime, 2))s - $($_.Exception.Message)"
                $folder.FileCount = 0
                $folder.TotalSize = 0
                $folder.TotalSizeGB = 0
            }
        } else {
            Write-Status "INITIAL CLOUD: '$($folder.Name)' not found for analysis"
            $folder.FileCount = 0
            $folder.TotalSize = 0
            $folder.TotalSizeGB = 0
        }
    }
    
    $analysisEndTime = Get-Date
    $analysisTime = ($analysisEndTime - $analysisStartTime).TotalSeconds
    $totalSizeProcessedGB = [math]::Round($totalSizeProcessed / 1GB, 3)
    
    Write-Status "INITIAL CLOUD: Analysis complete in $([math]::Round($analysisTime, 2)) seconds"
    Write-Status "INITIAL CLOUD: Total to process: $totalFilesProcessed files, $totalSizeProcessedGB GB"
    
    # Check for existing files that will be skipped
    Write-Status "INITIAL CLOUD: Checking for existing files that will be skipped..."
    $totalSkippedFiles = 0
    $skippedDetails = @()
    
    foreach ($folder in $foldersToProcess) {
        if (Test-Path $folder.SourcePath) {
            $skippedFiles = Test-OverwriteRisk -sourceFolder $folder.SourcePath -destinationBase $script:destinationDir -folderName $folder.Name
            if ($skippedFiles.Count -gt 0) {
                $totalSkippedFiles += $skippedFiles.Count
                $skippedDetails += [PSCustomObject]@{
                    FolderName = $folder.Name
                    SkippedFiles = $skippedFiles
                }
                Write-Status "INITIAL CLOUD: Found $($skippedFiles.Count) existing files in '$($folder.Name)' - these will be skipped (not overwritten)"
            }
        }
    }
    
    # Show skipped files info if any exist
    if ($totalSkippedFiles -gt 0) {
        Write-Status "INITIAL CLOUD: INFO - $totalSkippedFiles total files will be skipped across $($skippedDetails.Count) folders to preserve existing data"
        
        # Show informational dialog for folders with skipped files (if many)
        if ($totalSkippedFiles -gt 20) {
            foreach ($detail in $skippedDetails | Where-Object { $_.SkippedFiles.Count -gt 5 }) {
                Show-SkippedFilesInfo -skippedFiles $detail.SkippedFiles -folderName $detail.FolderName
            }
        }
    } else {
        Write-Status "INITIAL CLOUD: No existing files detected - all files will be copied"
    }
    
    # Initialize global progress tracking
    Initialize-GlobalProgress -totalOperations $foldersToProcess.Count -totalFiles $totalFilesProcessed -totalSize $totalSizeProcessed
    
    # Sort folders by size (largest first) to show progress on big items first
    $foldersToProcess = $foldersToProcess | Sort-Object TotalSize -Descending
    
    Write-Status "INITIAL CLOUD: Processing $($foldersToProcess.Count) folder operations (largest first)..."
    
    foreach ($folder in $foldersToProcess) {
        if ($script:cancelRequested) { 
            Write-Status "INITIAL CLOUD: Operation cancelled by user"
            return $false 
        }
        
        if (Test-Path $folder.SourcePath -PathType Container) {
            $folderStartTime = Get-Date
            Write-Status "INITIAL CLOUD: Starting copy of '$($folder.Name)' ($($folder.FileCount) files, $($folder.TotalSizeGB) GB)..."
            
            # Use the existing Windows-style copy with progress
            if ($script:useWindowsProgressDialog) {
                Initialize-WindowsProgressDialog -title "CopyAmigo - Initial Cloud Processing" -description "Copying $($folder.Name) ($($folder.TotalSizeGB) GB)"
            }
            
            # Add detailed timing for the copy operation itself
            $copyStartTime = Get-Date
            
            # Update global progress with current operation
            $script:globalProgress.CurrentOperation = $folder.Name
            
            $success = Start-WindowsStyleCopy -sourcePath $folder.SourcePath -destPath $folder.DestPath -folderName $folder.Name -operation "Copying $($folder.Name)"
            
            $copyEndTime = Get-Date
            $copyDuration = ($copyEndTime - $copyStartTime).TotalSeconds
            
            if ($script:useWindowsProgressDialog) {
                Close-WindowsProgressDialog
            }
            
            $folderEndTime = Get-Date
            $folderDuration = ($folderEndTime - $folderStartTime).TotalSeconds
            $transferRate = if ($folder.TotalSize -gt 0 -and $folderDuration -gt 0) { 
                [math]::Round(($folder.TotalSize / 1MB) / $folderDuration, 2) 
            } else { 0 }
            
            # Store timing information
            $folderTimings += @{
                Name = $folder.Name
                Duration = $folderDuration
                FileCount = $folder.FileCount
                SizeGB = $folder.TotalSizeGB
                TransferRateMBps = $transferRate
                Success = $success
            }
            
            if ($success) {
                $successCount++
                Write-Status "INITIAL CLOUD: Successfully copied '$($folder.Name)' in $([math]::Round($folderDuration, 2)) seconds ($transferRate MB/s)"
                
                # Update global progress tracking
                Complete-Operation -operationName $folder.Name -totalFiles $folder.FileCount -totalSize $folder.TotalSize
            } else {
                Write-Status "INITIAL CLOUD: Failed to copy '$($folder.Name)' after $([math]::Round($folderDuration, 2)) seconds"
                $overallSuccess = $false
                
                # Still mark operation as completed for progress tracking (failed operations count toward completion)
                Complete-Operation -operationName $folder.Name -totalFiles 0 -totalSize 0
            }
        } else {
            Write-Status "INITIAL CLOUD: Folder '$($folder.Name)' not found - skipping (Source: $($folder.SourcePath))"
            # Don't mark as failure since missing folders should be skipped per requirements
            
            # Mark operation as completed (skipped counts as completed for progress)
            Complete-Operation -operationName $folder.Name -totalFiles 0 -totalSize 0
            
            # Still track this for timing analysis
            $folderTimings += @{
                Name = $folder.Name
                Duration = 0
                FileCount = 0
                SizeGB = 0
                TransferRateMBps = 0
                Success = $false
                Skipped = $true
            }
        }
    }
    
    $operationEndTime = Get-Date
    $totalDuration = ($operationEndTime - $operationStartTime).TotalSeconds
    
    # Performance Summary
    Write-Status "=== INITIAL CLOUD PROCESSING PERFORMANCE SUMMARY ==="
    Write-Status "INITIAL CLOUD: Total operation time: $([math]::Round($totalDuration, 2)) seconds"
    Write-Status "INITIAL CLOUD: Analysis time: $([math]::Round($analysisTime, 2)) seconds ($([math]::Round(($analysisTime / $totalDuration) * 100, 1))% of total)"
    
    $copyTime = $totalDuration - $analysisTime
    Write-Status "INITIAL CLOUD: Actual copy time: $([math]::Round($copyTime, 2)) seconds ($([math]::Round(($copyTime / $totalDuration) * 100, 1))% of total)"
    
    if ($totalSizeProcessed -gt 0 -and $copyTime -gt 0) {
        $overallTransferRate = [math]::Round(($totalSizeProcessed / 1MB) / $copyTime, 2)
        Write-Status "INITIAL CLOUD: Overall transfer rate: $overallTransferRate MB/s"
    }
    
    Write-Status "INITIAL CLOUD: Folder-by-folder breakdown:"
    foreach ($timing in $folderTimings) {
        if ($timing.Skipped) {
            Write-Status "INITIAL CLOUD:   $($timing.Name): SKIPPED (not found)"
        } else {
            $status = if ($timing.Success) { "SUCCESS" } else { "FAILED" }
            Write-Status "INITIAL CLOUD:   $($timing.Name): $status - $([math]::Round($timing.Duration, 2))s, $($timing.FileCount) files, $($timing.SizeGB) GB, $($timing.TransferRateMBps) MB/s"
        }
    }
    
    Write-Status "INITIAL CLOUD: Completed $successCount folder operations"
    
    if ($successCount -eq 0) {
        Write-Status "INITIAL CLOUD: WARNING: No folders were found to copy"
        return $false
    }
    
    return $overallSuccess
}

function Copy-TerrascanData {
    Write-Status "=== TERRASCAN PROJECT SETUP ==="
    
    $destRoot = $script:destinationDir
    $overallSuccess = $true
    $successCount = 0
    
    # System Capabilities Analysis for Terrascan
    Write-Status "TERRASCAN: Analyzing system capabilities for optimal performance..."
    $systemAnalysis = Analyze-SystemCapabilities -sourcePath $sourceDir -destPath $script:destinationDir
    
    # Override the script's optimal parameters with our analysis
    $script:optimalParams = $systemAnalysis.OptimalParams
    Write-Status "TERRASCAN: Optimized for $($systemAnalysis.RecommendedStrategy) - $($systemAnalysis.OptimalThreads) threads"
    
    # Define the specific folders to copy for Terrascan Project Setup
    $foldersToProcess = @(
        @{
            Name = "Deliverable"
            SourcePath = Join-Path $sourceDir "Deliverable"
            DestPath = Join-Path $destRoot "Deliverable"
            CopyAll = $true
        },
        @{
            Name = "Orthomosaic\Finished Ortho Photos"
            SourcePath = Join-Path $sourceDir "Orthomosaic\Finished Ortho Photos"
            DestPath = Join-Path $destRoot "Orthomosaic\Finished Ortho Photos"
            CopyAll = $true
            RequiresValidation = $true
        },
        @{
            Name = "Planning\Boundary"
            SourcePath = Join-Path $sourceDir "Planning\Boundary"
            DestPath = Join-Path $destRoot "Planning\Boundary"
            CopyAll = $true
        },
        @{
            Name = "Planning\Work Orders"
            SourcePath = Join-Path $sourceDir "Planning\Work Orders"
            DestPath = Join-Path $destRoot "Planning\Work Orders"
            CopyAll = $true
        },
        @{
            Name = "Tscan\Settings"
            SourcePath = Join-Path $sourceDir "Tscan\Settings"
            DestPath = Join-Path $destRoot "Tscan\Settings"
            CopyAll = $true
        },
        @{
            Name = "Tscan\DGN"
            SourcePath = Join-Path $sourceDir "Tscan\DGN"
            DestPath = Join-Path $destRoot "Tscan\DGN"
            CopyAll = $true
        },
        @{
            Name = "Control"
            SourcePath = Join-Path $sourceDir "Control"
            DestPath = Join-Path $destRoot "Control"
            CopyAll = $true
        }
    )
    
    # Check for existing files that will be skipped
    Write-Status "TERRASCAN: Checking for existing files that will be skipped..."
    $totalSkippedFiles = 0
    $skippedDetails = @()
    
    foreach ($folder in $foldersToProcess) {
        if (Test-Path $folder.SourcePath) {
            $skippedFiles = Test-OverwriteRisk -sourceFolder $folder.SourcePath -destinationBase $destRoot -folderName $folder.Name
            if ($skippedFiles.Count -gt 0) {
                $totalSkippedFiles += $skippedFiles.Count
                $skippedDetails += [PSCustomObject]@{
                    FolderName = $folder.Name
                    SkippedFiles = $skippedFiles
                }
                Write-Status "TERRASCAN: Found $($skippedFiles.Count) existing files in '$($folder.Name)' - these will be skipped (not overwritten)"
            }
        }
    }
    
    # Show skipped files info if any exist
    if ($totalSkippedFiles -gt 0) {
        Write-Status "TERRASCAN: INFO - $totalSkippedFiles total files will be skipped to preserve existing data"
    } else {
        Write-Status "TERRASCAN: No existing files detected - all files will be copied"
    }
    
    Write-Status "TERRASCAN: Processing $($foldersToProcess.Count) folder operations..."
    $orthomosaicValidationWarning = ""
    
    foreach ($folder in $foldersToProcess) {
        if ($script:cancelRequested) { 
            Write-Status "TERRASCAN: Operation cancelled by user"
            return $false 
        }
        
        if (Test-Path $folder.SourcePath -PathType Container) {
            Write-Status "TERRASCAN: Copying '$($folder.Name)'..."
            
            # Use the existing Windows-style copy with progress
            if ($script:useWindowsProgressDialog) {
                Initialize-WindowsProgressDialog -title "CopyAmigo - Terrascan Project Setup" -description "Copying $($folder.Name)"
            }
            
            $success = Start-WindowsStyleCopy -sourcePath $folder.SourcePath -destPath $folder.DestPath -folderName $folder.Name -operation "Copying $($folder.Name)"
            
            if ($script:useWindowsProgressDialog) {
                Close-WindowsProgressDialog
            }
            
            if ($success) {
                $successCount++
                Write-Status "TERRASCAN: Successfully copied '$($folder.Name)'"
                
                # Special validation for Orthomosaic\Finished Ortho Photos
                if ($folder.RequiresValidation) {
                    Write-Status "TERRASCAN: Validating orthomosaic files in '$($folder.Name)'..."
                    $orthomosaicValidationWarning = Validate-OrthomosaicFiles -folderPath $folder.DestPath
                }
            } else {
                Write-Status "TERRASCAN: Failed to copy '$($folder.Name)'"
                $overallSuccess = $false
            }
        } else {
            Write-Status "TERRASCAN: Folder '$($folder.Name)' not found - skipping (Source: $($folder.SourcePath))"
            
            # For Orthomosaic\Finished Ortho Photos, create empty structure if source doesn't exist
            if ($folder.RequiresValidation) {
                Write-Status "TERRASCAN: Creating empty Orthomosaic\Finished Ortho Photos structure..."
                try {
                    New-Item -ItemType Directory -Path $folder.DestPath -Force | Out-Null
                    $orthomosaicValidationWarning = "No orthomosaic (JPG/ECW) found in Orthomosaic\Finished Ortho Photos."
                } catch {
                    Write-Status "TERRASCAN: Failed to create Orthomosaic\Finished Ortho Photos structure: $($_.Exception.Message)"
                }
            }
        }
    }
    
    Write-Status "TERRASCAN: Completed $successCount folder operations"
    
    # Process selected Tscan subfolders if any are checked
    if ($script:terrascanTscanCheckList -and $script:terrascanTscanCheckList.CheckedItems.Count -gt 0) {
        Write-Status "TERRASCAN: Processing selected Tscan subfolders..."
        
        foreach ($item in $script:terrascanTscanCheckList.CheckedItems) {
            if ($script:cancelRequested) { 
                Write-Status "TERRASCAN: Operation cancelled by user"
                return $false 
            }
            
            $subfolderName = $item.ToString()
            $sourceSubfolderPath = Join-Path $sourceDir "Tscan\$subfolderName"
            $destSubfolderPath = Join-Path $destRoot "Tscan\$subfolderName"
            
            if (Test-Path $sourceSubfolderPath -PathType Container) {
                Write-Status "TERRASCAN: Copying selected Tscan subfolder '$subfolderName'..."
                
                # Use the existing Windows-style copy with progress
                if ($script:useWindowsProgressDialog) {
                    Initialize-WindowsProgressDialog -title "CopyAmigo - Terrascan Project Setup" -description "Copying Tscan subfolder: $subfolderName"
                }
                
                $success = Start-WindowsStyleCopy -sourcePath $sourceSubfolderPath -destPath $destSubfolderPath -folderName "Tscan\$subfolderName" -operation "Copying Tscan subfolder: $subfolderName"
                
                if ($script:useWindowsProgressDialog) {
                    Close-WindowsProgressDialog
                }
                
                if ($success) {
                    $successCount++
                    Write-Status "TERRASCAN: Successfully copied Tscan subfolder '$subfolderName'"
                } else {
                    Write-Status "TERRASCAN: Failed to copy Tscan subfolder '$subfolderName'"
                    $overallSuccess = $false
                }
            } else {
                Write-Status "TERRASCAN: WARNING - Selected Tscan subfolder '$subfolderName' not found at source - skipping"
            }
        }
        
        Write-Status "TERRASCAN: Completed processing selected Tscan subfolders"
    } else {
        Write-Status "TERRASCAN: No Tscan subfolders selected for additional copying"
    }
    
    # Store validation warning for later use in completion popup
    if ($orthomosaicValidationWarning) {
        $script:terrascanValidationWarning = $orthomosaicValidationWarning
    }
    
    if ($successCount -eq 0) {
        Write-Status "TERRASCAN: WARNING: No folders were found to copy"
        return $false
    }
    
    return $overallSuccess
}

function Validate-OrthomosaicFiles {
    param(
        [string]$folderPath
    )
    
    if (-not (Test-Path $folderPath -PathType Container)) {
        return "No orthomosaic (JPG/ECW) found in Orthomosaic\Finished Ortho Photos."
    }
    
    try {
        # Recursively search for JPG, JPEG, or ECW files (case-insensitive)
        $orthomosaicFiles = Get-ChildItem $folderPath -Recurse -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Extension -match '\.(jpg|jpeg|ecw)$' }
        
        if ($orthomosaicFiles -and $orthomosaicFiles.Count -gt 0) {
            Write-Status "TERRASCAN: Found $($orthomosaicFiles.Count) orthomosaic file(s) in Orthomosaic\Finished Ortho Photos"
            return $null  # No warning needed
        } else {
            Write-Status "TERRASCAN: No orthomosaic files (JPG/JPEG/ECW) found in Orthomosaic\Finished Ortho Photos"
            return "No orthomosaic (JPG/ECW) found in Orthomosaic\Finished Ortho Photos."
        }
    } catch {
        Write-Status "TERRASCAN: Error validating orthomosaic files: $($_.Exception.Message)"
        return "No orthomosaic (JPG/ECW) found in Orthomosaic\Finished Ortho Photos."
    }
}

function Analyze-SystemCapabilities {
    param(
        [string]$sourcePath,
        [string]$destPath,
        [System.Windows.Forms.TextBox]$debugTextBox = $null
    )
    
    $analysis = @{
        CPUCores = 0
        TotalRAM_GB = 0
        AvailableRAM_GB = 0
        SourceDriveType = "Unknown"
        DestDriveType = "Unknown"
        SourceIsLocal = $false
        DestIsLocal = $false
        SourceIsSSD = $false
        DestIsSSD = $false
        NetworkBandwidth = "Unknown"
        OptimalThreads = 8
        OptimalParams = ""
        RecommendedStrategy = ""
    }
    
    if ($debugTextBox) { Add-DebugMessage $debugTextBox "=== SYSTEM ANALYSIS STARTING ===" }
    
    try {
        # CPU Analysis
        $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
        $analysis.CPUCores = $cpu.NumberOfLogicalProcessors
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "CPU: $($cpu.Name)" }
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "Logical Cores: $($analysis.CPUCores)" }
        
        # Memory Analysis
        $memory = Get-WmiObject -Class Win32_ComputerSystem
        $analysis.TotalRAM_GB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        
        $availableMemory = Get-Counter "\Memory\Available MBytes" -ErrorAction SilentlyContinue
        if ($availableMemory) {
            $analysis.AvailableRAM_GB = [math]::Round($availableMemory.CounterSamples[0].CookedValue / 1024, 2)
        }
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "RAM: $($analysis.TotalRAM_GB) GB total, $($analysis.AvailableRAM_GB) GB available" }
        
        # Source Drive Analysis
        if ($sourcePath) {
            $sourceDrive = Split-Path $sourcePath -Qualifier
            if ($sourceDrive) {
                $analysis.SourceIsLocal = $sourceDrive -match "^[A-Z]:$"
                
                if ($analysis.SourceIsLocal) {
                    # Check if it's SSD
                    $disk = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $sourceDrive }
                    if ($disk) {
                        $physicalDisk = Get-WmiObject -Class Win32_DiskDrive | Where-Object { $_.Index -eq $disk.DriveType }
                        if ($physicalDisk) {
                            $analysis.SourceIsSSD = $physicalDisk.MediaType -like "*SSD*" -or $physicalDisk.Model -like "*SSD*"
                            $analysis.SourceDriveType = if ($analysis.SourceIsSSD) { "SSD" } else { "HDD" }
                        }
                    }
                } else {
                    $analysis.SourceDriveType = "Network"
                }
                if ($debugTextBox) { Add-DebugMessage $debugTextBox "Source: $sourceDrive -> $($analysis.SourceDriveType)" }
            }
        }
        
        # Destination Drive Analysis
        if ($destPath) {
            $destDrive = Split-Path $destPath -Qualifier
            if ($destDrive) {
                $analysis.DestIsLocal = $destDrive -match "^[A-Z]:$"
                
                if ($analysis.DestIsLocal) {
                    # Check if it's SSD
                    $disk = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $destDrive }
                    if ($disk) {
                        $physicalDisk = Get-WmiObject -Class Win32_DiskDrive | Where-Object { $_.Index -eq $disk.DriveType }
                        if ($physicalDisk) {
                            $analysis.DestIsSSD = $physicalDisk.MediaType -like "*SSD*" -or $physicalDisk.Model -like "*SSD*"
                            $analysis.DestDriveType = if ($analysis.DestIsSSD) { "SSD" } else { "HDD" }
                        }
                    }
                } else {
                    $analysis.DestDriveType = "Network"
                }
                if ($debugTextBox) { Add-DebugMessage $debugTextBox "Destination: $destDrive -> $($analysis.DestDriveType)" }
            }
        }
        
        # Network Speed Test (if network involved)
        if (!$analysis.SourceIsLocal -or !$analysis.DestIsLocal) {
            if ($debugTextBox) { Add-DebugMessage $debugTextBox "Network copy detected - analyzing network performance..." }
            # Quick network test could go here
            $analysis.NetworkBandwidth = "Gigabit" # Default assumption
        }
        
    } catch {
        if ($debugTextBox) { Add-DebugMessage $debugTextBox "Error during system analysis: $($_.Exception.Message)" }
    }
    
    # Calculate Optimal Parameters
    $analysis = Optimize-CopyParameters $analysis $debugTextBox
    
    if ($debugTextBox) { Add-DebugMessage $debugTextBox "=== OPTIMIZATION RESULTS ===" }
    if ($debugTextBox) { Add-DebugMessage $debugTextBox "Strategy: $($analysis.RecommendedStrategy)" }
    if ($debugTextBox) { Add-DebugMessage $debugTextBox "Optimal Threads: $($analysis.OptimalThreads)" }
    if ($debugTextBox) { Add-DebugMessage $debugTextBox "Robocopy Params: $($analysis.OptimalParams)" }
    if ($debugTextBox) { Add-DebugMessage $debugTextBox "=== ANALYSIS COMPLETE ===" }
    
    return $analysis
}

function Optimize-CopyParameters {
    param(
        $analysis,
        [System.Windows.Forms.TextBox]$debugTextBox = $null
    )
    
    # Base parameters (fast, minimal logging, skip existing files)
    $baseParams = "/E /COPY:DAT /R:1 /W:1 /XN"
    # /XN = eXclude Newer files (skip if destination file exists and is same or newer than source)
    
    # Determine optimal strategy based on hardware
    if ($analysis.SourceIsLocal -and $analysis.DestIsLocal) {
        # Local to Local Copy
        if ($analysis.SourceIsSSD -and $analysis.DestIsSSD) {
            # SSD to SSD - Maximum performance
            $analysis.OptimalThreads = [math]::Min(32, $analysis.CPUCores * 2)
            $analysis.RecommendedStrategy = "SSD-to-SSD High Performance"
            $analysis.OptimalParams = "$baseParams /MT:$($analysis.OptimalThreads) /J"  # /J = unbuffered I/O
        } elseif ($analysis.SourceIsSSD -or $analysis.DestIsSSD) {
            # Mixed SSD/HDD
            $analysis.OptimalThreads = [math]::Min(16, $analysis.CPUCores)
            $analysis.RecommendedStrategy = "Mixed SSD/HDD Performance"
            $analysis.OptimalParams = "$baseParams /MT:$($analysis.OptimalThreads)"
        } else {
            # HDD to HDD
            $analysis.OptimalThreads = [math]::Min(8, $analysis.CPUCores)
            $analysis.RecommendedStrategy = "HDD-to-HDD Standard"
            $analysis.OptimalParams = "$baseParams /MT:$($analysis.OptimalThreads)"
        }
    } elseif (!$analysis.SourceIsLocal -and !$analysis.DestIsLocal) {
        # Network to Network
        $analysis.OptimalThreads = 2
        $analysis.RecommendedStrategy = "Network-to-Network Conservative"
        $analysis.OptimalParams = "$baseParams /MT:$($analysis.OptimalThreads) /IPG:10"  # 10ms gap between packets
    } elseif (!$analysis.SourceIsLocal -or !$analysis.DestIsLocal) {
        # Network involved
        if ($analysis.AvailableRAM_GB -gt 8) {
            $analysis.OptimalThreads = 4
            $analysis.RecommendedStrategy = "Network Copy Optimized"
            $analysis.OptimalParams = "$baseParams /MT:$($analysis.OptimalThreads)"
        } else {
            $analysis.OptimalThreads = 2
            $analysis.RecommendedStrategy = "Network Copy Conservative"
            $analysis.OptimalParams = "$baseParams /MT:$($analysis.OptimalThreads)"
        }
    }
    
    # Memory-based adjustments
    if ($analysis.AvailableRAM_GB -lt 4) {
        # Low memory - reduce threads
        $analysis.OptimalThreads = [math]::Max(1, [math]::Floor($analysis.OptimalThreads / 2))
        $analysis.RecommendedStrategy += " (Low Memory)"
    } elseif ($analysis.AvailableRAM_GB -gt 16) {
        # High memory - can be more aggressive
        $analysis.OptimalThreads = [math]::Min($analysis.OptimalThreads * 1.5, 64)
        $analysis.RecommendedStrategy += " (High Memory)"
    }
    
    # Update the final parameters
    $analysis.OptimalParams = $analysis.OptimalParams -replace "/MT:\d+", "/MT:$($analysis.OptimalThreads)"
    
    # Add progress suppression for speed (no verbose logging)
    $analysis.OptimalParams += " /NP /NDL /NJH /NJS"  # No progress, no dir list, no job header/summary
    
    return $analysis
}

function Create-DebugWindow {
    # Create debug window
    $debugForm = New-Object System.Windows.Forms.Form
    $debugForm.Text = "Initial Cloud Processing - Debug Log"
    $debugForm.Size = New-Object System.Drawing.Size(800, 600)
    $debugForm.StartPosition = "Manual"
    
    # Position it to the right of the main window
    $mainFormLocation = $script:form.Location
    $debugForm.Location = New-Object System.Drawing.Point(($mainFormLocation.X + $script:form.Width + 10), $mainFormLocation.Y)
    
    $debugForm.FormBorderStyle = "Sizable"
    $debugForm.MaximizeBox = $true
    $debugForm.MinimizeBox = $true
    $debugForm.TopMost = $true  # Keep it on top so it's always visible
    
    # Create text box for debug output
    $debugTextBox = New-Object System.Windows.Forms.TextBox
    $debugTextBox.Name = "DebugTextBox"
    $debugTextBox.Multiline = $true
    $debugTextBox.ScrollBars = "Vertical"
    $debugTextBox.ReadOnly = $true
    $debugTextBox.Location = New-Object System.Drawing.Point(10, 10)
    $debugTextBox.Size = New-Object System.Drawing.Size(760, 520)
    $debugTextBox.BackColor = [System.Drawing.Color]::Black
    $debugTextBox.ForeColor = [System.Drawing.Color]::Yellow
    $debugTextBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $debugTextBox.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $debugForm.Controls.Add($debugTextBox)
    
    # Add close button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close Debug Window"
    $closeButton.Location = New-Object System.Drawing.Point(10, 540)
    $closeButton.Size = New-Object System.Drawing.Size(150, 30)
    $closeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $closeButton.Add_Click({ $debugForm.Close() })
    $debugForm.Controls.Add($closeButton)
    
    # Add clear button
    $clearButton = New-Object System.Windows.Forms.Button
    $clearButton.Text = "Clear Log"
    $clearButton.Location = New-Object System.Drawing.Point(170, 540)
    $clearButton.Size = New-Object System.Drawing.Size(100, 30)
    $clearButton.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $clearButton.Add_Click({ $debugTextBox.Clear() })
    $debugForm.Controls.Add($clearButton)
    
    # Show the window
    $debugForm.Show()
    
    return $debugForm
}

function Add-DebugMessage {
    param(
        [System.Windows.Forms.TextBox]$textBox,
        [string]$message
    )
    
    if ($textBox) {
        $timestamp = Get-Date -Format "HH:mm:ss.fff"
        $fullMessage = "[$timestamp] $message"
        
        # Add to text box and scroll to bottom
        $textBox.AppendText("$fullMessage`r`n")
        $textBox.SelectionStart = $textBox.Text.Length
        $textBox.ScrollToCaret()
        
        # Force UI update
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function OnMainFolderChanged {
    # Ensure required controls exist before proceeding
    if (-not $script:mainFolderDropdown -or -not $script:subfolderDropdown) {
        return
    }

    $selectedMainFolder = $script:mainFolderDropdown.SelectedItem

    # Clear previous selections
    $script:subfolderDropdown.Items.Clear()
    $script:selectedSubfolders = @()

    if ($selectedMainFolder) {
        $subfolders = Get-TscanSubfolders $selectedMainFolder

        if ($subfolders -and $subfolders.Count -gt 0) {
            foreach ($subfolder in $subfolders) {
                $script:subfolderDropdown.Items.Add($subfolder) | Out-Null
            }
            $script:subfolderDropdown.Enabled = $true
        } else {
            $script:subfolderDropdown.Items.Add("No valid folders found") | Out-Null
            $script:subfolderDropdown.Enabled = $false
        }
    } else {
        $script:subfolderDropdown.Enabled = $false
    }

    Update-SubfolderCount
    Update-CopyButtonState
}

function Update-SubfolderCount {
    if (-not $script:subfolderDropdown -or -not $script:selectionCountLabel) {
        return
    }

    $script:selectedSubfolders = @()
    $totalItems = $script:subfolderDropdown.Items.Count

    for ($i = 0; $i -lt $totalItems; $i++) {
        if ($script:subfolderDropdown.GetItemChecked($i)) {
            # Safely handle any potential null items
            $item = $script:subfolderDropdown.Items[$i]
            if ($null -ne $item) {
                $script:selectedSubfolders += $item.ToString()
            }
        }
    }

    if ($script:selectionCountLabel) {
        $script:selectionCountLabel.Text = "Selected: $($script:selectedSubfolders.Count)"
    }
}

function Update-CopyButtonState {
    if (-not $script:copyButton) { return }

    $canCopy = $false

    if ($script:destinationDir -and (Test-Path (Split-Path $script:destinationDir -Parent))) {
        # Ensure radio buttons exist before accessing their properties to avoid null reference errors
        if ($script:initialCloudRadio -and $script:initialCloudRadio.Checked) {
            $canCopy = $true
        } elseif ($script:tscanRadio -and $script:tscanRadio.Checked) {
            $canCopy = $script:selectedSubfolders.Count -gt 0
        } elseif ($script:orthomosaicRadio -and $script:orthomosaicRadio.Checked) {
            $canCopy = $true
        } elseif ($script:terrascanRadio -and $script:terrascanRadio.Checked) {
            $canCopy = $true
        }
    }

    $script:copyButton.Enabled = $canCopy
}

function OnSubfolderItemCheck {
    # Use timer to ensure checkbox state is updated after the CheckedListBox state settles
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 50
    $timer.Add_Tick({
        param($sender, $eventArgs)
        # Use the sender (the Timer instance) rather than captured variable to avoid null reference
        $sender.Stop()
        $sender.Dispose()
        Update-SubfolderCount
        Update-CopyButtonState
    })
    $timer.Start()
}

function OnTerrascanTscanItemCheck {
    # Use timer to ensure checkbox state is updated after the CheckedListBox state settles
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 50
    $timer.Add_Tick({
        param($sender, $eventArgs)
        # Use the sender (the Timer instance) rather than captured variable to avoid null reference
        $sender.Stop()
        $sender.Dispose()
        Update-CopyButtonState
    })
    $timer.Start()
}

function OnCopyClick {
    $script:cancelRequested = $false
    $script:copyButton.Enabled = $false
    $script:cancelButton.Enabled = $true
    $script:progressBar.Value = 0
    $script:statusTextBox.Clear()
    
    # Set global start time immediately when copy button is clicked
    $script:copyStats.StartTime = Get-Date
    
    # Reset logging variables
    $script:lastLoggedPercent = -1
    $script:lastLoggedFile = ""
    $script:totalOperationFiles = 0
    $script:totalOperationSize = 0
    
    Write-Status "=== CopyAmigo $scriptVersion ==="
    
    $overallSuccess = $true
    
    try {
        # Initialize optimizations
        if ($script:cancelRequested) { return }
        Initialize-DestinationFolder
        
        if ($script:cancelRequested) { return }
        Initialize-Optimization
        
        # Each data source is now self-contained and handles its own folder requirements
        
        # Copy selected data type with optimization
        if ($script:initialCloudRadio.Checked) {
            if ($script:cancelRequested) { return }
            Write-Status "Starting Initial Cloud Processing workflow..."
            if (-not (Copy-InitialCloudData)) {
                $overallSuccess = $false
            }
        } elseif ($script:tscanRadio.Checked) {
            if ($script:cancelRequested) { return }
            Write-Status "Starting Tscan data copy with standard project folders..."
            if (-not (Copy-TscanData)) {
                $overallSuccess = $false
            }
        } elseif ($script:orthomosaicRadio.Checked) {
            if ($script:cancelRequested) { return }
            Write-Status "Starting Orthomosaic Processing workflow..."
            if (-not (Copy-OrthomosaicData)) {
                $overallSuccess = $false
            }
        } elseif ($script:terrascanRadio.Checked) {
            if ($script:cancelRequested) { return }
            Write-Status "Starting Terrascan Project Setup workflow..."
            if (-not (Copy-TerrascanData)) {
                $overallSuccess = $false
            }
        }
        
        # Clean up any remaining processes
        Stop-AllProcesses
        
        # Calculate final statistics
        if ($script:copyStats.StartTime) {
            Write-CleanSummary -totalFiles $script:totalOperationFiles -totalSize $script:totalOperationSize -operation "All operations complete"
        }
        
        # Final status and notification
        if ($script:cancelRequested) {
            Write-Status "=== COPY PROCESS CANCELLED ==="
            [System.Windows.Forms.MessageBox]::Show(
                "Copy process was cancelled by user.`n`nAny partially copied data may remain in the destination folder.",
                "Operation Cancelled",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        } else {
            Update-Progress 100
            
            # Show success message
            if ($script:initialCloudRadio.Checked) {
                Write-Status "Initial Cloud Processing data copied successfully"
            } elseif ($script:terrascanRadio.Checked) {
                Write-Status "Terrascan Project Setup data copied successfully"
            } elseif ($script:orthomosaicRadio.Checked) {
                Write-Status "Orthomosaic Processing data copied successfully"
            } elseif ($script:tscanRadio.Checked) {
                $folderCount = $script:selectedSubfolders.Count
                Write-Status "Tscan data copied successfully: $folderCount selected folders plus standard project folders"
            }
            
            if ($overallSuccess) {
                # Build summary string
                $sizeStr = Format-FileSize $script:totalOperationSize
                $summaryMsg = "Successfully copied $($script:totalOperationFiles) files ($sizeStr)"
                
                # Add Terrascan validation warning if present
                if ($script:terrascanRadio.Checked -and $script:terrascanValidationWarning) {
                    $summaryMsg += "`n`n$($script:terrascanValidationWarning)"
                }
                
                [System.Windows.Forms.MessageBox]::Show(
                    $summaryMsg,
                    "Copy Complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            } else {
                $sizeStr = Format-FileSize $script:totalOperationSize
                $summaryMsg = "Copied $($script:totalOperationFiles) files ($sizeStr) with some warnings.\nPlease check the log for details."
                [System.Windows.Forms.MessageBox]::Show(
                    $summaryMsg,
                    "Copy Complete with Warnings",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            }
        }
        
    } catch {
        $errorMessage = "A critical error occurred during the copy process:`n`n$($_.Exception.Message)`n`nPlease check the log for details."
        Write-Status "CRITICAL ERROR: $($_.Exception.Message)"
        
        [System.Windows.Forms.MessageBox]::Show(
            $errorMessage,
            "Copy Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } finally {
        # Always clean up
        Stop-AllProcesses
        
        # Clean up parallel jobs
        if ($script:parallelJobs.Count -gt 0) {
            foreach ($jobInfo in $script:parallelJobs) {
                try {
                    Stop-Job -Job $jobInfo.Job -ErrorAction SilentlyContinue
                    Remove-Job -Job $jobInfo.Job -Force -ErrorAction SilentlyContinue
                } catch {
                    # Ignore cleanup errors
                }
            }
            $script:parallelJobs = @()
        }
        
        $script:copyButton.Enabled = $true
        $script:cancelButton.Enabled = $false
        $script:cancelRequested = $false
        
        # Force final progress update
        if (-not $script:cancelRequested) {
            Update-Progress 100
        }
    }
}

function OnCancelClick {
    Write-Status "=== CANCELLATION REQUESTED ==="
    $script:cancelRequested = $true
    $script:copyButton.Enabled = $false
    $script:cancelButton.Enabled = $false
    
    Write-Status "CANCEL: Stopping all active processes..."
    
    # Clean up active processes
    Cleanup-ActiveProcesses
    
    # Reset UI
    $script:copyButton.Enabled = $true
    $script:cancelButton.Enabled = $false
    $script:progressBar.Value = 0
    
    Write-Status "CANCEL: Cancellation completed - UI reset"
    Write-Status "=== CANCELLATION COMPLETED ==="
}

function Cleanup-ActiveProcesses {
    Write-Status "DEBUG: Cleanup-ActiveProcesses called"
    
    if ($script:activeProcesses -and $script:activeProcesses.Count -gt 0) {
        Write-Status "DEBUG: Cleaning up $($script:activeProcesses.Count) active processes"
        
        foreach ($process in $script:activeProcesses) {
            try {
                if (-not $process.HasExited) {
                    Write-Status "DEBUG: Killing process PID: $($process.Id)"
                    $process.Kill()
                    Write-Status "DEBUG: Process killed successfully"
                }
            } catch {
                Write-Status "DEBUG: Error killing process: $($_.Exception.Message)"
            }
            
            try {
                $process.Dispose()
                Write-Status "DEBUG: Process disposed successfully"
            } catch {
                Write-Status "DEBUG: Error disposing process: $($_.Exception.Message)"
            }
        }
        
        $script:activeProcesses = @()
        Write-Status "DEBUG: All active processes cleaned up"
    } else {
        Write-Status "DEBUG: No active processes to clean up"
    }
}

function Browse-DestinationFolder {
    # Always use C:\Projects for destinations, regardless of source projects root
    if (-not $script:destinationRoot -or -not (Test-Path $script:destinationRoot)) {
        try { 
            New-Item -ItemType Directory -Path 'C:\Projects' -Force | Out-Null 
            $script:destinationRoot = 'C:\Projects'
        } catch {
            Write-Status "ERROR: Cannot create C:\Projects directory - $($_.Exception.Message)"
            return
        }
    }

    $script:destinationDir = Join-Path $script:destinationRoot $script:projectFolderName
    try {
        if (-not (Test-Path $script:destinationDir)) {
            New-Item -ItemType Directory -Path $script:destinationDir -Force | Out-Null
        }
    } catch {
        Write-Status "ERROR: Cannot create destination '$script:destinationDir' - $($_.Exception.Message)"
    }

    if ($script:destinationTextBox) {
        $script:destinationTextBox.Text = $script:destinationDir
        $script:destinationTextBox.ForeColor = [System.Drawing.Color]::Black
    }
    Write-Status "Destination updated to: $script:destinationDir"
    Update-CopyButtonState
}

function Auto-DetectDestination {
    # Set destination to C:\Projects\[ProjectName] when a project is selected
    if (-not $script:destinationRoot -or -not (Test-Path $script:destinationRoot)) {
        try { 
            New-Item -ItemType Directory -Path 'C:\Projects' -Force | Out-Null 
            $script:destinationRoot = 'C:\Projects'
        } catch {
            Write-Status "ERROR: Cannot create C:\Projects directory - $($_.Exception.Message)"
            return
        }
    }

    $script:destinationDir = Join-Path $script:destinationRoot $script:projectFolderName

    try {
        if (-not (Test-Path $script:destinationDir)) {
            New-Item -ItemType Directory -Path $script:destinationDir -Force | Out-Null
        }
    } catch {
        Write-Status "ERROR: Cannot create destination '$script:destinationDir' - $($_.Exception.Message)"
    }

    if ($script:destinationTextBox) {
        $script:destinationTextBox.Text = $script:destinationDir
        $script:destinationTextBox.ForeColor = [System.Drawing.Color]::Blue
        $script:destinationTextBox.Refresh()
    }
    Write-Status "Destination updated to: $script:destinationDir"
    Update-CopyButtonState
}

function Create-GUI {
    # Create main form
    $script:form = New-Object System.Windows.Forms.Form
    $script:form.Text = "CopyAmigo $scriptVersion"
    $script:form.Size = New-Object System.Drawing.Size(700, 1085)
    $script:form.StartPosition = "CenterScreen"
    $script:form.FormBorderStyle = "FixedDialog"
    $script:form.MaximizeBox = $false
    $script:form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    # Shared tooltip for helpful hints
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.ShowAlways = $true
    $toolTip.InitialDelay = 300
    $toolTip.AutoPopDelay = 8000
    $toolTip.ReshowDelay = 100
    
    # Header label
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Text = "CopyAmigo - Project Data Copy Tool"
    $headerLabel.Location = New-Object System.Drawing.Point(20, 20)
    $headerLabel.Size = New-Object System.Drawing.Size(400, 30)
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $script:form.Controls.Add($headerLabel)
    
    # Project info
    $script:infoLabel = New-Object System.Windows.Forms.Label
    $script:infoLabel.Text = "Project: $projectFolderName`nSource: $sourceDir"
    $script:infoLabel.Location = New-Object System.Drawing.Point(20, 60)
    $script:infoLabel.Size = New-Object System.Drawing.Size(400, 40)
    $script:infoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $script:form.Controls.Add($script:infoLabel)
    
    # Search Projects button
    $script:searchProjectsButton = New-Object System.Windows.Forms.Button
    $script:searchProjectsButton.Text = "Search Projects..."
    $script:searchProjectsButton.Location = New-Object System.Drawing.Point(440, 60)
    $script:searchProjectsButton.Size = New-Object System.Drawing.Size(120, 35)
    $script:searchProjectsButton.Add_Click({ 
        # Removed Write-Host to prevent popups in executable
        try {
            # Removed Write-Host to prevent popups in executable
            Show-ProjectSearchModal
            # Removed Write-Host to prevent popups in executable
        } catch {
            # Removed Write-Host to prevent popups in executable
            [System.Windows.Forms.MessageBox]::Show("Error opening project search: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $script:form.Controls.Add($script:searchProjectsButton)
    $toolTip.SetToolTip($script:searchProjectsButton, "Search for and select a project from the Projects root directory.")
    
    # Set Destination button
    $script:browseButton = New-Object System.Windows.Forms.Button
    $script:browseButton.Text = "Set Destination"
    $script:browseButton.Location = New-Object System.Drawing.Point(20, 120)
    $script:browseButton.Size = New-Object System.Drawing.Size(200, 40)
    $script:browseButton.Add_Click({ Browse-DestinationFolder })
    $script:form.Controls.Add($script:browseButton)
    $toolTip.SetToolTip($script:browseButton, "Select where to copy your project data. A project folder will be created automatically.")
    
    # Destination text box
    $script:destinationTextBox = New-Object System.Windows.Forms.TextBox
    $script:destinationTextBox.Location = New-Object System.Drawing.Point(240, 125)
    $script:destinationTextBox.Size = New-Object System.Drawing.Size(400, 28)
    $script:destinationTextBox.ReadOnly = $true
    $script:destinationTextBox.Text = "C:\Projects"
    $script:form.Controls.Add($script:destinationTextBox)
    $toolTip.SetToolTip($script:destinationTextBox, "Shows the automatic destination path (C:\Projects\[ProjectName]) for your project copy.")
    
    # Data source selection
    $sourceGroupBox = New-Object System.Windows.Forms.GroupBox
    $sourceGroupBox.Text = "Choose Copy Mode"
    $sourceGroupBox.Location = New-Object System.Drawing.Point(20, 170)
    $sourceGroupBox.Size = New-Object System.Drawing.Size(650, 675)
    $script:form.Controls.Add($sourceGroupBox)
    
    # Instruction label for copy mode selection
    $script:copyModeInstructionLabel = New-Object System.Windows.Forms.Label
    $script:copyModeInstructionLabel.Text = "IMPORTANT: Please select a project first to enable copy mode selection"
    $script:copyModeInstructionLabel.Location = New-Object System.Drawing.Point(20, 25)
    $script:copyModeInstructionLabel.Size = New-Object System.Drawing.Size(600, 25)
    $script:copyModeInstructionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $script:copyModeInstructionLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    $script:copyModeInstructionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $sourceGroupBox.Controls.Add($script:copyModeInstructionLabel)
    
    # 1. Initial Cloud Processing radio button
    $script:initialCloudRadio = New-Object System.Windows.Forms.RadioButton
    $script:initialCloudRadio.Text = "Raw Data Processing - Everything needed to process a raw dataset"
    $script:initialCloudRadio.Location = New-Object System.Drawing.Point(20, 60)
    $script:initialCloudRadio.Size = New-Object System.Drawing.Size(600, 25)
    $script:initialCloudRadio.Checked = $true
    $script:initialCloudRadio.Enabled = $false  # Disabled until project is selected
    $script:initialCloudRadio.Add_CheckedChanged({ Update-CopyButtonState })
    $sourceGroupBox.Controls.Add($script:initialCloudRadio)
    $toolTip.SetToolTip($script:initialCloudRadio, "Best for initial cloud processing workflows. Includes control data, planning files, and all raw survey data.")
    
    # 2. Terrascan Project Setup radio button
    $script:terrascanRadio = New-Object System.Windows.Forms.RadioButton
    $script:terrascanRadio.Text = "Terrascan Project Setup - Complete project setup for Terrascan workflows"
    $script:terrascanRadio.Location = New-Object System.Drawing.Point(20, 95)
    $script:terrascanRadio.Size = New-Object System.Drawing.Size(600, 25)
    $script:terrascanRadio.Enabled = $false  # Disabled until project is selected
    $script:terrascanRadio.Add_CheckedChanged({ 
        $script:terrascanGroupBox.Enabled = $script:terrascanRadio.Checked
        if ($script:terrascanRadio.Checked) {
            # Populate the Terrascan Tscan subfolder checklist
            $script:terrascanTscanCheckList.Items.Clear()
            $terrascanSubfolders = Get-TerrascanTscanSubfolders
            if ($terrascanSubfolders -and $terrascanSubfolders.Count -gt 0) {
                foreach ($subfolder in $terrascanSubfolders) {
                    $script:terrascanTscanCheckList.Items.Add($subfolder) | Out-Null
                }
                $script:terrascanTscanCheckList.Enabled = $true
            } else {
                $script:terrascanTscanCheckList.Items.Add("No Tscan subfolders found") | Out-Null
                $script:terrascanTscanCheckList.Enabled = $false
            }
        }
        Update-CopyButtonState 
    })
    $sourceGroupBox.Controls.Add($script:terrascanRadio)
    $toolTip.SetToolTip($script:terrascanRadio, "Complete setup for Terrascan workflows. Includes deliverables, orthomosaic imagery, planning data, Tscan/DGN, Tscan/Settings, plus selected additional Tscan subfolders.")
    
    # Terrascan options group (positioned between Terrascan and Orthomosaic radio buttons)
    $script:terrascanGroupBox = New-Object System.Windows.Forms.GroupBox
    $script:terrascanGroupBox.Text = "Terrascan Tscan Options"
    $script:terrascanGroupBox.Location = New-Object System.Drawing.Point(50, 120)
    $script:terrascanGroupBox.Size = New-Object System.Drawing.Size(580, 200)
    $script:terrascanGroupBox.Enabled = $false
    $sourceGroupBox.Controls.Add($script:terrascanGroupBox)
    
    # Terrascan Tscan subfolder label
    $terrascanTscanLabel = New-Object System.Windows.Forms.Label
    $terrascanTscanLabel.Text = "Select Extra Tscan Subfolders:"
    $terrascanTscanLabel.Location = New-Object System.Drawing.Point(20, 25)
    $terrascanTscanLabel.Size = New-Object System.Drawing.Size(200, 20)
    $script:terrascanGroupBox.Controls.Add($terrascanTscanLabel)
    
    # Terrascan Tscan subfolder checklist
    $script:terrascanTscanCheckList = New-Object System.Windows.Forms.CheckedListBox
    $script:terrascanTscanCheckList.CheckOnClick = $true
    $script:terrascanTscanCheckList.IntegralHeight = $false
    $script:terrascanTscanCheckList.Location = New-Object System.Drawing.Point(20, 50)
    $script:terrascanTscanCheckList.Size = New-Object System.Drawing.Size(540, 140)
    $script:terrascanTscanCheckList.Enabled = $false
    $script:terrascanTscanCheckList.Add_ItemCheck({ OnTerrascanTscanItemCheck })
    $script:terrascanGroupBox.Controls.Add($script:terrascanTscanCheckList)
    
    # 3. Orthomosaic Processing radio button
    $script:orthomosaicRadio = New-Object System.Windows.Forms.RadioButton
    $script:orthomosaicRadio.Text = "Orthomosaic Processing - Minimal files needed for orthomosaic creation"
    $script:orthomosaicRadio.Location = New-Object System.Drawing.Point(20, 330)
    $script:orthomosaicRadio.Size = New-Object System.Drawing.Size(600, 25)
    $script:orthomosaicRadio.Enabled = $false  # Disabled until project is selected
    $script:orthomosaicRadio.Add_CheckedChanged({ Update-CopyButtonState })
    $sourceGroupBox.Controls.Add($script:orthomosaicRadio)
    $toolTip.SetToolTip($script:orthomosaicRadio, "Optimized for orthomosaic creation. Includes only essential files: control points, camera data, and reference files.")
    
    # 4. Tscan radio button
    $script:tscanRadio = New-Object System.Windows.Forms.RadioButton
    $script:tscanRadio.Text = "Tscan - Standard project folders plus selected Tscan data"
    $script:tscanRadio.Location = New-Object System.Drawing.Point(20, 365)
    $script:tscanRadio.Size = New-Object System.Drawing.Size(600, 25)
    $script:tscanRadio.Enabled = $false  # Disabled until project is selected
    $script:tscanRadio.Add_CheckedChanged({ 
        $script:tscanGroupBox.Enabled = $script:tscanRadio.Checked
        if ($script:tscanRadio.Checked) {
            $script:mainFolderDropdown.Items.Clear()
            $mainFolders = Get-TscanMainFolders
            if ($mainFolders -and $mainFolders.Count -gt 0) {
                foreach ($folder in $mainFolders) {
                    $script:mainFolderDropdown.Items.Add($folder) | Out-Null
                }
                $script:mainFolderDropdown.Enabled = $true
            } else {
                $script:mainFolderDropdown.Items.Add("No data found") | Out-Null
                $script:mainFolderDropdown.Enabled = $false
            }
        }
        Update-CopyButtonState 
    })
    $sourceGroupBox.Controls.Add($script:tscanRadio)
    $toolTip.SetToolTip($script:tscanRadio, "Copies standard project folders (Control, Planning subsets, Orthomosaic photos, Tscan/DGN, Tscan/Settings) plus your selected Tscan subfolders.")


    
    # Tscan options group
    $script:tscanGroupBox = New-Object System.Windows.Forms.GroupBox
    $script:tscanGroupBox.Text = "Tscan Options"
    $script:tscanGroupBox.Location = New-Object System.Drawing.Point(50, 395)
    $script:tscanGroupBox.Size = New-Object System.Drawing.Size(580, 270)
    $script:tscanGroupBox.Enabled = $false
    $sourceGroupBox.Controls.Add($script:tscanGroupBox)
    
    # Main folder label
    $mainFolderLabel = New-Object System.Windows.Forms.Label
    $mainFolderLabel.Text = "Main Folder:"
    $mainFolderLabel.Location = New-Object System.Drawing.Point(20, 25)
    $mainFolderLabel.Size = New-Object System.Drawing.Size(80, 20)
    $script:tscanGroupBox.Controls.Add($mainFolderLabel)
    
    # Main folder dropdown
    $script:mainFolderDropdown = New-Object System.Windows.Forms.ComboBox
    $script:mainFolderDropdown.DropDownStyle = "DropDownList"
    $script:mainFolderDropdown.Location = New-Object System.Drawing.Point(110, 22)
    $script:mainFolderDropdown.Size = New-Object System.Drawing.Size(200, 25)
    $script:mainFolderDropdown.Enabled = $false
    $script:mainFolderDropdown.Add_SelectedIndexChanged({ OnMainFolderChanged })
    $script:tscanGroupBox.Controls.Add($script:mainFolderDropdown)
    
    # Subfolder label (now above the list)
    $subfolderLabel = New-Object System.Windows.Forms.Label
    $subfolderLabel.Text = "Select Subfolders:"
    $subfolderLabel.Location = New-Object System.Drawing.Point(20, 60)
    $subfolderLabel.Size = New-Object System.Drawing.Size(150, 20)
    $script:tscanGroupBox.Controls.Add($subfolderLabel)
    
    # Subfolder checklist (half the previous size)
    $script:subfolderDropdown = New-Object System.Windows.Forms.CheckedListBox
    $script:subfolderDropdown.CheckOnClick = $true
    $script:subfolderDropdown.IntegralHeight = $false  # Allow custom height, not limited to item count
    $script:subfolderDropdown.Location = New-Object System.Drawing.Point(20, 85)
    $script:subfolderDropdown.Size = New-Object System.Drawing.Size(540, 200)  # Half the previous size
    $script:subfolderDropdown.Enabled = $false
    $script:subfolderDropdown.Add_ItemCheck({ OnSubfolderItemCheck })
    $script:tscanGroupBox.Controls.Add($script:subfolderDropdown)
    
    # Selection count label (moved up)
    $script:selectionCountLabel = New-Object System.Windows.Forms.Label
    $script:selectionCountLabel.Text = "Selected: 0"
    $script:selectionCountLabel.Location = New-Object System.Drawing.Point(420, 290)
    $script:selectionCountLabel.Size = New-Object System.Drawing.Size(140, 20)
    $script:selectionCountLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $script:selectionCountLabel.ForeColor = [System.Drawing.Color]::Blue
    $script:tscanGroupBox.Controls.Add($script:selectionCountLabel)
    

    
    # Copy button
    $script:copyButton = New-Object System.Windows.Forms.Button
    $script:copyButton.Text = "Start Copy"
    $script:copyButton.Location = New-Object System.Drawing.Point(20, 865)
    $script:copyButton.Size = New-Object System.Drawing.Size(170, 40)
    $script:copyButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $script:copyButton.ForeColor = [System.Drawing.Color]::White
    $script:copyButton.Enabled = $false
    $script:copyButton.Add_Click({ OnCopyClick })
    $script:form.Controls.Add($script:copyButton)
    $toolTip.SetToolTip($script:copyButton, "Start copying using the selected mode.")
    
    # Cancel button
    $script:cancelButton = New-Object System.Windows.Forms.Button
    $script:cancelButton.Text = "Cancel"
    $script:cancelButton.Location = New-Object System.Drawing.Point(180, 865)
    $script:cancelButton.Size = New-Object System.Drawing.Size(110, 40)
    $script:cancelButton.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
    $script:cancelButton.ForeColor = [System.Drawing.Color]::White
    $script:cancelButton.Enabled = $false
    $script:cancelButton.Add_Click({ OnCancelClick })
    $script:form.Controls.Add($script:cancelButton)
    $toolTip.SetToolTip($script:cancelButton, "Cancel the current operation.")
    
    # Progress bar
    $script:progressBar = New-Object System.Windows.Forms.ProgressBar
    $script:progressBar.Location = New-Object System.Drawing.Point(290, 865)
    $script:progressBar.Size = New-Object System.Drawing.Size(360, 40)
    $script:form.Controls.Add($script:progressBar)
    $toolTip.SetToolTip($script:progressBar, "Overall progress of the copy operation.")
    

    
    # Status text box
    $script:statusTextBox = New-Object System.Windows.Forms.TextBox
    $script:statusTextBox.Multiline = $true
    $script:statusTextBox.ScrollBars = "Vertical"
    $script:statusTextBox.ReadOnly = $true
    $script:statusTextBox.Location = New-Object System.Drawing.Point(20, 915)
    $script:statusTextBox.Size = New-Object System.Drawing.Size(650, 150)
    $script:statusTextBox.BackColor = [System.Drawing.Color]::Black
    $script:statusTextBox.ForeColor = [System.Drawing.Color]::LimeGreen
    $script:statusTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $script:statusTextBox.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $script:form.Controls.Add($script:statusTextBox)
    $toolTip.SetToolTip($script:statusTextBox, "Live status and logs.")
    
    # Form closing event
    $script:form.Add_FormClosing({
        $script:cancelRequested = $true
        Stop-AllProcesses
    })
    
    return $script:form
}

# End of Create-GUI function

# Main execution
try {
    # Removed Write-Host to prevent popups in executable
    # Removed Write-Host to prevent popups in executable
    
    $script:form = Create-GUI
    
    $script:form.Add_Shown({
        $script:form.Activate()
        # Don't auto-set destination on initial load - just show C:\Projects
        $script:destinationDir = $script:destinationRoot
        Update-CopyButtonState
        
        # Enable copy mode selection if a project is already selected
        if ($script:projectFolderName -and $script:projectFolderName -ne "Beta 3") {
            Enable-CopyModeSelection
        } else {
            # Ensure instruction label shows the correct message when no project is selected
            if ($script:copyModeInstructionLabel) {
                $script:copyModeInstructionLabel.Text = "IMPORTANT: Please select a project first to enable copy mode selection"
                $script:copyModeInstructionLabel.ForeColor = [System.Drawing.Color]::DarkOrange
            }
        }
    })
    
    [System.Windows.Forms.Application]::Run($script:form)
    
} catch {
    # Removed Write-Host to prevent popups in executable
    # Removed Write-Host to prevent popups in executable
    [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)", "CopyAmigo Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
} finally {
    Stop-AllProcesses
} 