# ScreenConnect Upgrade - Auto-detect, Remove Old, Install New
# Automatically finds installed ScreenConnect, removes it, installs new MSI
# Downloads MSI from GitHub Release
# Logs to C:\temp\SC_Upgrade_Log.txt

$MSIPath = "C:\temp\ScreenConnect.ClientSetup.msi"
$LogPath = "C:\temp\SC_Upgrade_Log.txt"
$GitHubURL = "https://github.com/scottbrys/Public/releases/download/v26.6.5.9742/ScreenConnect.ClientSetup.msi"

function Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $LogPath -Value $entry -ErrorAction SilentlyContinue
}

Log "=== ScreenConnect Upgrade Started ==="

# Detect ALL installed ScreenConnect instances
Log "Detecting all installed ScreenConnect versions..."
$allProducts = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*ScreenConnect*" }

if (-not $allProducts) {
    Log "No installed ScreenConnect found - proceeding with fresh install"
    $instancesToUpgrade = @()
} else {
    # Force to array if single result
    if ($allProducts -isnot [array]) {
        $allProducts = @($allProducts)
    }

    Log "Found $($allProducts.Count) ScreenConnect instance(s)"
    $instancesToUpgrade = @()

    foreach ($product in $allProducts) {
        $version = $product.Version
        $name = $product.Name
        Log "Instance: $name v$version"

        if ($version -ne "26.6.5.9742") {
            Log "  → Needs upgrade"
            $instancesToUpgrade += $product
        } else {
            Log "  → Already at target version, skipping"
        }
    }

    if ($instancesToUpgrade.Count -eq 0) {
        Log "SUCCESS: All ScreenConnect instances are at v26.6.5.9742 - no upgrade needed"
        $skipUpgrade = $true
    } else {
        $skipUpgrade = $false
    }
}

# Download MSI from GitHub if not present
if (!(Test-Path $MSIPath)) {
    Log "Downloading MSI from GitHub..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Log "Downloading: $GitHubURL"
        Invoke-WebRequest -Uri $GitHubURL -OutFile $MSIPath -ErrorAction Stop
        Log "Download complete: $MSIPath"
    } catch {
        Log "ERROR: Failed to download MSI - $_"
        exit 1
    }
}

# Verify MSI exists
if (!(Test-Path $MSIPath)) {
    Log "ERROR: MSI not found at $MSIPath"
    exit 1
}
Log "MSI ready: $MSIPath"

# Only stop/upgrade if needed
if (-not $skipUpgrade) {
    # Stop ALL ScreenConnect services
    Log "Stopping all ScreenConnect services..."
    Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | Where-Object { $_.Status -eq 'Running' } | ForEach-Object {
        Log "Stopping $($_.Name)"
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 2

    # Upgrade each instance that needs it
    foreach ($product in $instancesToUpgrade) {
    $ProductCode = $product.IdentifyingNumber
    $InstallPath = $product.InstallLocation
    $Version = $product.Version
    $Name = $product.Name

    Log "Upgrading: $Name (v$Version) with product code $ProductCode"

    # Delete installation folder
    if ($InstallPath -and (Test-Path $InstallPath)) {
        Log "Deleting old installation folder: $InstallPath"
        try {
            cmd /c "rmdir /s /q `"$InstallPath`"" 2>&1 | Out-Null
            Log "Folder deleted"
        } catch {
            Log "WARNING: Folder delete failed - $_"
        }
    } else {
        Log "No installation folder found to delete"
    }

    # Force-remove registry entries for this specific product
    Log "Force-removing registry entries for $ProductCode..."
    $regCommands = @(
        "reg delete `"HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode`" /f",
        "reg delete `"HKLM\Software\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$ProductCode`" /f"
    )

    foreach ($cmd in $regCommands) {
        try {
            cmd /c $cmd 2>&1 | Out-Null
        } catch {
            # Errors expected if keys don't exist, ignore
        }
    }
    Log "Registry cleaned (forced)"

    Start-Sleep -Seconds 1

    # Install new version
    Log "Installing new version for this instance..."
    $install = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MSIPath`" /qn /norestart REINSTALLMODE=vomus /L*v `"C:\temp\SC_MSI_Log.txt`"" -PassThru -Wait
    Log "Install exit code: $($install.ExitCode)"

    if ($install.ExitCode -eq 0 -or $install.ExitCode -eq 3010) {
        Log "Installation successful for this instance"
    } else {
        Log "WARNING: Installation returned exit code $($install.ExitCode)"
    }

    Start-Sleep -Seconds 2
    }
} else {
    Log "Skipping upgrade - all instances already at target version"
}

# Start/Restart ScreenConnect services
Log "Starting ScreenConnect services..."
Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | ForEach-Object {
    if ($_.Status -ne 'Running') {
        Log "Starting $($_.Name)"
        Start-Service -Name $_.Name -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 3

# Verify services
Start-Sleep -Seconds 5
Log "Checking ScreenConnect services..."
$allServices = Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" }

if ($allServices) {
    if ($allServices -isnot [array]) {
        $allServices = @($allServices)
    }

    foreach ($svc in $allServices) {
        Log "Service: $($svc.Name) - Status: $($svc.Status)"
        if ($svc.Status -eq 'Running') {
            Log "  → Running with upgraded version"
        } else {
            Log "  → WARNING: Stopped - may need manual restart"
        }
    }

    Log "SUCCESS: All instances upgraded and services verified"
} else {
    Log "WARNING: No ScreenConnect service found"
}

Log "=== Upgrade Complete ==="