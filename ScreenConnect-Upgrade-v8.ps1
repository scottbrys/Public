# ScreenConnect Upgrade v8 - Multi-Installation Handler
# Handles multiple ScreenConnect installations independently
# If any version < 26.6.5.9742, uninstall it and install target
# If any version >= 26.6.5.9742, leave it alone

param(
    [string]$TargetVersion = "26.6.5.9742"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] === ScreenConnect Upgrade v8 Started ===" -ForegroundColor Cyan

# Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$msiUrl = "https://raw.githubusercontent.com/scottbrys/Public/main/ScreenConnect.ClientSetup.msi"
$msiPath = "C:\temp\ScreenConnect.ClientSetup.msi"

# Registry paths to search
$registryPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Find ALL ScreenConnect installations
$installations = @()

foreach ($basePath in $registryPaths) {
    if (Test-Path $basePath) {
        Get-ChildItem $basePath | ForEach-Object {
            $regPath = $_.PSPath
            $displayName = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).DisplayName
            $displayVersion = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).DisplayVersion
            $uninstallString = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).UninstallString

            if ($displayName -like "*ScreenConnect*" -and $displayVersion) {
                $installations += [PSCustomObject]@{
                    DisplayName = $displayName
                    Version = $displayVersion
                    RegPath = $regPath
                    UninstallString = $uninstallString
                }
            }
        }
    }
}

if ($installations.Count -eq 0) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] No ScreenConnect installations found. Exiting." -ForegroundColor Yellow
    exit 0
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] Found $($installations.Count) ScreenConnect installation(s):" -ForegroundColor Cyan

$needsUpgrade = @()
$alreadyCurrent = @()

foreach ($install in $installations) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] Installation: $($install.DisplayName)"
    Write-Host "[$timestamp]   Version: $($install.Version)"

    try {
        $current = [version]$install.Version
        $target = [version]$TargetVersion

        if ($current -lt $target) {
            Write-Host "[$timestamp]   Status: NEEDS UPGRADE" -ForegroundColor Yellow
            $needsUpgrade += $install
        } else {
            Write-Host "[$timestamp]   Status: Already current or newer" -ForegroundColor Green
            $alreadyCurrent += $install
        }
    } catch {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp]   ERROR: Could not parse version" -ForegroundColor Red
    }
}

Write-Host ""

# Handle installations that need upgrade
if ($needsUpgrade.Count -gt 0) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] Processing $($needsUpgrade.Count) installation(s) for upgrade..." -ForegroundColor Cyan

    # Download MSI
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] Downloading MSI from GitHub..." -ForegroundColor White
    try {
        (New-Object Net.WebClient).DownloadFile($msiUrl, $msiPath)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] Download complete: $msiPath" -ForegroundColor Green
    } catch {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] ERROR downloading MSI: $_" -ForegroundColor Red
        exit 1
    }

    # Process each installation that needs upgrade
    foreach ($install in $needsUpgrade) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] Uninstalling $($install.DisplayName) v$($install.Version)..." -ForegroundColor Yellow

        # Stop ScreenConnect service
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] Stopping ScreenConnect service..." -ForegroundColor White
        Stop-Service -Name ScreenConnect.ClientService -ErrorAction SilentlyContinue -Force
        Start-Sleep -Seconds 2

        # Uninstall via MSI using UninstallString or GUID
        if ($install.UninstallString -match '{[A-F0-9\-]+}') {
            $guid = $matches[0]
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Host "[$timestamp] Uninstalling GUID: $guid" -ForegroundColor White
            $uninstallResult = & msiexec.exe /x $guid /quiet /norestart
            Start-Sleep -Seconds 3
        } else {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Host "[$timestamp] WARNING: Could not find GUID for uninstall" -ForegroundColor Yellow
        }

        # Install new version
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] Installing ScreenConnect v$TargetVersion..." -ForegroundColor Cyan
        $installResult = & msiexec.exe /i $msiPath /quiet /norestart

        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Host "[$timestamp] Installation successful (Exit code: $LASTEXITCODE)" -ForegroundColor Green
        } else {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Host "[$timestamp] WARNING: Installation exit code: $LASTEXITCODE" -ForegroundColor Yellow
        }

        Start-Sleep -Seconds 2
    }
} else {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] No installations need upgrade." -ForegroundColor Green
}

# Clean up registry for removed versions
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] Cleaning up stale registry entries..." -ForegroundColor Cyan

$cleanupPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Classes\Installer\Products"
)

foreach ($path in $cleanupPaths) {
    if (Test-Path $path) {
        Get-ChildItem $path | ForEach-Object {
            $displayName = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($displayName -like "*ScreenConnect*") {
                $version = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayVersion
                try {
                    $v = [version]$version
                    $t = [version]$TargetVersion
                    if ($v -lt $t) {
                        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        Write-Host "[$timestamp] Removing stale registry entry: $displayName v$version" -ForegroundColor Yellow
                        Remove-Item $_.PSPath -Force -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
        }
    }
}

# Restart service
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] Restarting ScreenConnect service..." -ForegroundColor Cyan
Start-Service -Name ScreenConnect.ClientService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Verify final state
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] Final ScreenConnect installation state:" -ForegroundColor Cyan

$finalInstalls = @()
foreach ($basePath in $registryPaths) {
    if (Test-Path $basePath) {
        Get-ChildItem $basePath | ForEach-Object {
            $displayName = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            $displayVersion = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayVersion
            if ($displayName -like "*ScreenConnect*" -and $displayVersion) {
                $finalInstalls += [PSCustomObject]@{
                    DisplayName = $displayName
                    Version = $displayVersion
                }
            }
        }
    }
}

$finalInstalls | ForEach-Object {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp]   $($_.DisplayName) v$($_.Version)" -ForegroundColor Green
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] === Complete ===" -ForegroundColor Cyan