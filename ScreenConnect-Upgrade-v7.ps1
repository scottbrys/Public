# ScreenConnect Upgrade Script v7 - Version-Aware
# Only upgrades if current version < 26.6.5.9742

$ErrorActionPreference = "SilentlyContinue"
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === ScreenConnect Upgrade v7 Started ==="

# Get current version from registry
$CurrentVersion = $null
$VersionFound = $false

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Checking current ScreenConnect version..."

try {
    $reg = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*ScreenConnect*'} | Select-Object -First 1
    if (-not $reg) {
        $reg = Get-ItemProperty 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*ScreenConnect*'} | Select-Object -First 1
    }
    if ($reg) {
        $CurrentVersion = $reg.DisplayVersion
        $VersionFound = $true
    }
} catch {}

if ($VersionFound) {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Current version: $CurrentVersion"
    
    # Compare versions
    try {
        $current = [version]$CurrentVersion
        $target = [version]'26.6.5.9742'
        
        if ($current -ge $target) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Version $CurrentVersion is already at or newer than 26.6.5.9742"
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] No upgrade needed. Exiting."
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === Complete ==="
            Read-Host "Press Enter"
            exit 0
        }
    } catch {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Version comparison failed. Proceeding with upgrade."
    }
} else {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] No ScreenConnect installation found. Will proceed with fresh install."
}

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Proceeding with upgrade to v26.6.5.9742..."

# Search ALL possible registry locations for ScreenConnect
$toDelete = @()

# Standard Uninstall paths
$toDelete += Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'}
$toDelete += Get-ChildItem 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'}

# Non-standard: Classes\Installer\Products
$toDelete += Get-ChildItem 'HKLM:\Software\Classes\Installer\Products' -ErrorAction SilentlyContinue | Where-Object {(Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ProductName -like '*ScreenConnect*'}

# URL Scheme keys
$toDelete += Get-ChildItem 'HKLM:\Software\Classes' -ErrorAction SilentlyContinue | Where-Object {$_.PSChildName -like 'sc-*'}

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Found $($toDelete.Count) ScreenConnect registry entries to remove"

# Stop services
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Stopping services..."
Get-Service -ErrorAction SilentlyContinue | Where-Object {$_.Name -like '*ScreenConnect*'} | Stop-Service -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Delete each registry entry
$toDelete | ForEach-Object {
    Write-Host "  Deleting: $($_.PSPath)"
    Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Delete folders
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Deleting installation folders..."
Remove-Item 'C:\Program Files (x86)\ScreenConnect*' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\Software\ScreenConnect' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\Software\Wow6432Node\ScreenConnect' -Recurse -Force -ErrorAction SilentlyContinue

# Download new version
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Downloading v26.6.5.9742..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/scottbrys/Public/main/ScreenConnect.ClientSetup.msi', 'C:\Temp\ScreenConnect.ClientSetup.msi')
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Download successful"
} catch {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: Download failed: $_"
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === Failed ==="
    Read-Host "Press Enter"
    exit 1
}

# Install new version
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Installing..."
$result = & msiexec.exe /I C:\Temp\ScreenConnect.ClientSetup.msi /qn /norestart
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] MSI exit code: $result"

Start-Sleep -Seconds 5

# Verify installation
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Verifying installation..."
$installed = $false
try {
    $installed = Get-ChildItem 'C:\Program Files (x86)\ScreenConnect*' -ErrorAction SilentlyContinue
    if ($installed) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Installation verified: $installed"
    }
} catch {}

# Start services
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting services..."
Start-Sleep 2
Get-Service -ErrorAction SilentlyContinue | Where-Object {$_.Name -like '*ScreenConnect*'} | Start-Service -ErrorAction SilentlyContinue

# Final version check
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Performing final version check..."
$NewVersion = $null
try {
    $newReg = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*ScreenConnect*'} | Select-Object -First 1
    if (-not $newReg) {
        $newReg = Get-ItemProperty 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*ScreenConnect*'} | Select-Object -First 1
    }
    if ($newReg) {
        $NewVersion = $newReg.DisplayVersion
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] New version installed: $NewVersion"
    }
} catch {}

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === Complete ==="
Read-Host "Press Enter"