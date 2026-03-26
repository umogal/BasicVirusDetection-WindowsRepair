# ===============================
# Windows Ultimate Reset and Repair TUI
# ===============================

$logFile = "$env:USERPROFILE\Desktop\UltimateRepairLog_$(Get-Date -Format yyyyMMdd_HHmmss).txt"

function Write-Log {
    param([string]$Message)
    Add-Content -Path $logFile -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $Message"
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================" -ForegroundColor Cyan
    Write-Host "  Windows Ultimate Reset and Repair  " -ForegroundColor Cyan
    Write-Host "==========================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "1. Repair Network"
    Write-Host "2. System Repair (DISM, SFC, MCBUILD)"
    Write-Host "3. Clean Temporary Files & Cache"
    Write-Host "4. Reset Windows Update Components"
    Write-Host "5. Run Health Diagnostics"
    Write-Host "6. Exit"
    Write-Host ""
}

function Create-RestorePoint {
    Write-Host "Creating system restore point..." -ForegroundColor Magenta
    Write-Log "Creating system restore point."
    try {
        Checkpoint-Computer -Description "PreRepairRestorePoint" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "Restore point created successfully." -ForegroundColor Green
        Write-Log "Restore point created successfully."
    }
    catch {
        Write-Host "Failed to create restore point: $_" -ForegroundColor Red
        Write-Log "Failed to create restore point: $_"
    }
}

function Show-Progress {
    param([string]$Message)
    for ($i=0; $i -le 100; $i+=20) {
        Write-Progress -Activity $Message -Status "$i% Complete" -PercentComplete $i
        Start-Sleep -Milliseconds 200
    }
    Write-Progress -Activity $Message -Completed
}

function Run-Command {
    param (
        [string]$Desc,
        [string]$Cmd
    )
    Write-Host "`nDoing: $Desc" -ForegroundColor Yellow
    Write-Host "Running command: $Cmd" -ForegroundColor Cyan
    Write-Log "Doing: $Desc | Command: $Cmd"

    try {
        $output = Invoke-Expression $Cmd
        Write-Host "Output: $output" -ForegroundColor Gray
        Write-Host "Status: Successful" -ForegroundColor Green
        Write-Log "Status: Successful | Output: $output"
    }
    catch {
        Write-Host "Status: Failed - $_" -ForegroundColor Red
        Write-Log "Status: Failed - $_"
    }
}

function Repair-Network {
    Create-RestorePoint
    Clear-Host
    Write-Host "Repairing Network..." -ForegroundColor Green

    $networkCmds = @(
        @{Desc="Resetting Winsock"; Cmd="netsh winsock reset"},
        @{Desc="Resetting IP stack"; Cmd="netsh int ip reset"},
        @{Desc="Releasing IP"; Cmd="ipconfig /release"},
        @{Desc="Renewing IP"; Cmd="ipconfig /renew"},
        @{Desc="Flushing DNS"; Cmd="ipconfig /flushdns"},
        @{Desc="Registering DNS"; Cmd="ipconfig /registerdns"},
        @{Desc="Clearing ARP cache"; Cmd="arp -d *"},
        @{Desc="Resetting NetBIOS over TCP/IP"; Cmd="nbtstat -R"},
        @{Desc="Re-registering NetBIOS names"; Cmd="nbtstat -RR"}
    )

    $jobs = @()
    foreach ($cmd in $networkCmds) {
        $jobs += Start-Job -ScriptBlock { param($d,$c) Show-Progress "Executing $d"; Run-Command $d $c } -ArgumentList $cmd.Desc, $cmd.Cmd
    }
    $jobs | Wait-Job | Receive-Job
    Remove-Job -State Completed
    Write-Host "`nNetwork repair completed." -ForegroundColor Green
    Pause
}

function Repair-System {
    Create-RestorePoint
    Clear-Host
    Write-Host "System Repair..." -ForegroundColor Green

    $systemCmds = @(
        @{Desc="Running DISM online repair"; Cmd="DISM /Online /Cleanup-Image /RestoreHealth"},
        @{Desc="Running System File Checker"; Cmd="sfc /scannow"},
        @{Desc="Rebuilding MCB database"; Cmd="mcbuilder"}
    )

    foreach ($cmd in $systemCmds) {
        Show-Progress "Executing $($cmd.Desc)"
        Run-Command $cmd.Desc $cmd.Cmd
    }
    Write-Host "`nSystem repair completed." -ForegroundColor Green
    Pause
}

function Clean-TempFiles {
    Create-RestorePoint
    Clear-Host
    Write-Host "Cleaning Temporary Files..." -ForegroundColor Green

    $tempCmds = @(
        @{Desc="Cleaning temp folder"; Cmd="Remove-Item -Path $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue"},
        @{Desc="Cleaning Windows temp"; Cmd="Remove-Item -Path C:\Windows\Temp\* -Recurse -Force -ErrorAction SilentlyContinue"},
        @{Desc="Cleaning Prefetch"; Cmd="Remove-Item -Path C:\Windows\Prefetch\* -Recurse -Force -ErrorAction SilentlyContinue"}
    )

    foreach ($cmd in $tempCmds) {
        Show-Progress "Executing $($cmd.Desc)"
        Run-Command $cmd.Desc $cmd.Cmd
    }
    Write-Host "`nTemporary files cleaned." -ForegroundColor Green
    Pause
}

function Reset-WindowsUpdate {
    Create-RestorePoint
    Clear-Host
    Write-Host "Resetting Windows Update Components..." -ForegroundColor Green

    $wuCmds = @(
        @{Desc="Stopping Windows Update services"; Cmd="net stop wuauserv & net stop bits & net stop cryptsvc & net stop msiserver"},
        @{Desc="Renaming SoftwareDistribution folder"; Cmd="Rename-Item C:\Windows\SoftwareDistribution SoftwareDistribution.old -Force"},
        @{Desc="Renaming Catroot2 folder"; Cmd="Rename-Item C:\Windows\System32\catroot2 catroot2.old -Force"},
        @{Desc="Restarting Windows Update services"; Cmd="net start wuauserv & net start bits & net start cryptsvc & net start msiserver"}
    )

    foreach ($cmd in $wuCmds) {
        Show-Progress "Executing $($cmd.Desc)"
        Run-Command $cmd.Desc $cmd.Cmd
    }
    Write-Host "`nWindows Update reset completed." -ForegroundColor Green
    Pause
}

function Run-HealthDiagnostics {
    Clear-Host
    Write-Host "Running Health Diagnostics..." -ForegroundColor Green

    # Disk health
    Show-Progress "Checking disk health"
    Run-Command "Check disk health" "chkdsk C: /F /R"

    # Network ping
    Show-Progress "Testing network connectivity"
    Run-Command "Ping google.com" "ping google.com"

    # DNS resolution test
    Show-Progress "Testing DNS resolution"
    Run-Command "Resolve DNS for microsoft.com" "nslookup microsoft.com"

    Write-Host "`nHealth diagnostics completed." -ForegroundColor Green
    Pause
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host "Select an option (1-6)"
    switch ($choice) {
        "1" { Repair-Network }
        "2" { Repair-System }
        "3" { Clean-TempFiles }
        "4" { Reset-WindowsUpdate }
        "5" { Run-HealthDiagnostics }
        "6" { Write-Host "Exiting..."; break }
        default { Write-Host "Invalid option, try again." -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
} while ($true)
