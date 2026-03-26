<#

    #>

# 1. Administrative Enforcement
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevation required. Restarting as Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

$logFile = "$env:USERPROFILE\Desktop\SystemRepairLog_$(Get-Date -Format yyyyMMdd).log"

# --- Helper Functions ---

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append
}

function Invoke-Action {
    param (
        [string]$Description,
        [scriptblock]$ScriptBlock
    )
    Write-Host "`n[*] $Description..." -ForegroundColor Cyan
    Write-Log "Executing: $Description"
    try {
        & $ScriptBlock
        Write-Host "[+] Success" -ForegroundColor Green
        Write-Log "Success: $Description"
    }
    catch {
        Write-Host "[-] Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
    }
}

function Create-RestorePoint {
    Write-Host "Checking System Restore status..." -ForegroundColor Magenta
    try {
        # Check if System Protection is enabled
        if ((Get-ComputerRestorePoint).Count -eq 0 -or $true) {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "PreRepair_$(Get-Date -Format HHmm)" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
            Write-Host "[+] Restore point created." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[!] Restore point skipped (standard 24hr limit or disabled)." -ForegroundColor Yellow
    }
}

# --- Core Logic Functions ---

function Repair-Network {
    Create-RestorePoint
    $cmds = @(
        { netsh winsock reset },
        { netsh int ip reset },
        { ipconfig /release },
        { ipconfig /renew },
        { ipconfig /flushdns },
        { nbtstat -R },
        { nbtstat -RR },
        { netsh advfirewall reset }
    )
    
    foreach ($c in $cmds) { Invoke-Action "Network Stack Optimization" $c }
    Write-Host "`nNetwork repair complete. A reboot is recommended." -ForegroundColor Green
    Pause
}

function Repair-System {
    Create-RestorePoint
    Invoke-Action "DISM Component Store Repair" { DISM /Online /Cleanup-Image /RestoreHealth }
    Invoke-Action "SFC System File Verification" { sfc /scannow }
    Invoke-Action "MCBuilder Optimization" { mcbuilder }
    Pause
}

function Clean-TempFiles {
    $targets = @("$env:TEMP\*", "C:\Windows\Temp\*", "C:\Windows\Prefetch\*")
    foreach ($path in $targets) {
        Invoke-Action "Cleaning $path" { 
            Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue 
        }
    }
    Pause
}

function Reset-WindowsUpdate {
    Create-RestorePoint
    $services = @("wuauserv", "bits", "cryptsvc", "msiserver")
    
    Invoke-Action "Stopping Update Services" {
        foreach ($s in $services) { 
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue 
        }
    }

    # Handle file locks with a brief wait
    Start-Sleep -Seconds 2

    Invoke-Action "Renaming SoftwareDistribution" {
        if (Test-Path "C:\Windows\SoftwareDistribution") {
            $stamp = Get-Date -Format "yyyyMMddHHmm"
            Rename-Item -Path "C:\Windows\SoftwareDistribution" -NewName "SoftwareDistribution.old.$stamp" -Force
        }
    }

    Invoke-Action "Restarting Services" {
        foreach ($s in $services) { 
            Start-Service -Name $s -ErrorAction SilentlyContinue 
        }
    }
    Pause
}

function Run-HealthDiagnostics {
    Invoke-Action "DNS Integrity Check" { Resolve-DnsName google.com -QuickRuntime }
    Invoke-Action "Disk Health Analysis" { Get-PhysicalDisk | Select-Object DeviceID, FriendlyName, OperationalStatus, HealthStatus }
    Write-Host "`n[!] To run a full CHKDSK, the system must reboot." -ForegroundColor Yellow
    $confirm = Read-Host "Schedule CHKDSK on next reboot? (y/n)"
    if ($confirm -eq 'y') { chkdsk C: /f }
    Pause
}

# --- TUI Logic ---

do {
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "   WINDOWS ULTIMATE REPAIR TUI (v2.0)         " -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host " 1. Repair Network Stack"
    Write-Host " 2. System Integrity Repair (DISM/SFC)"
    Write-Host " 3. Deep Clean Temp/Cache"
    Write-Host " 4. Full Reset Windows Update"
    Write-Host " 5. Diagnostics & Disk Check"
    Write-Host " 6. Exit"
    Write-Host "----------------------------------------------"
    
    $choice = Read-Host "Command"
    switch ($choice) {
        "1" { Repair-Network }
        "2" { Repair-System }
        "3" { Clean-TempFiles }
        "4" { Reset-WindowsUpdate }
        "5" { Run-HealthDiagnostics }
        "6" { Exit }
    }
} while ($true)
