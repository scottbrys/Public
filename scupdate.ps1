# ScreenConnect Upgrade - VERBOSE with screen output
# Registry-based detection, detailed logging for troubleshooting

$MSIPath = "C:\temp\ScreenConnect.ClientSetup.msi"
$LogPath = "C:\temp\SC_Upgrade_Log.txt"
$GitHubURL = "https://raw.githubusercontent.com/scottbrys/Public/main/ScreenConnect.ClientSetup.msi"

function Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $LogPath -Value $entry -ErrorAction SilentlyContinue
}

if (-not (Test-Path "C:\temp")) {
    New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
}

Log "=== ScreenConnect Upgrade Started ==="
Log "Detecting all installed ScreenConnect versions..."

$instancesToUpgrade = @()
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        $uninstallKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        
        foreach ($key in $uninstallKeys) {
            $displayName = $key.GetValue("DisplayName")
            $displayVersion = $key.GetValue("DisplayVersion")
            
            if ($displayName -like "*ScreenConnect*") {
                $productCode = Split-Path -Leaf $key.PSPath
                Log "Instance: $displayName v$displayVersion (ProductCode: $productCode)"
                
                if ($displayVersion -ne "26.6.5.9742") {
                    Log "  -> Needs upgrade"
                    $instancesToUpgrade += @{
                        Name = $displayName
                        Version = $displayVersion
                        ProductCode = $productCode
                        RegistryPath = $key.PSPath
                    }
                } else {
                    Log "  -> Already at target version, skipping"
                }
            }
        }
    }
}

if ($instancesToUpgrade.Count -eq 0) {
    Log "No instances needing upgrade found"
    $skipUpgrade = $true
} else {
    Log "Found $($instancesToUpgrade.Count) instance(s) needing upgrade"
    $skipUpgrade = $false
}

if (!(Test-Path $MSIPath)) {
    Log "Downloading MSI from GitHub..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Log "Downloading: $GitHubURL"
        Invoke-WebRequest -Uri $GitHubURL -OutFile $MSIPath -ErrorAction Stop
        Log "Download complete: $MSIPath"
    } catch {
        Log "ERROR: Failed to download MSI - $($_.Exception.Message)"
        Read-Host "Press Enter to close"
        exit 1
    }
}

if (!(Test-Path $MSIPath)) {
    Log "ERROR: MSI not found at $MSIPath"
    Read-Host "Press Enter to close"
    exit 1
}
Log "MSI ready: $MSIPath"

if (-not $skipUpgrade) {
    Log "Starting upgrade process..."
    Log "Stopping all ScreenConnect services..."
    try {
        Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | Where-Object { $_.Status -eq 'Running' } | ForEach-Object {
            Log "  Stopping $($_.Name)..."
            Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
        Log "All services stopped"
    } catch {
        Log "ERROR during service stop: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 2

    foreach ($product in $instancesToUpgrade) {
        $ProductCode = $product.ProductCode
        $Name = $product.Name
        $Version = $product.Version

        Log "Upgrading: $Name (v$Version)"

        try {
            $installKey = Get-Item -Path $product.RegistryPath -ErrorAction SilentlyContinue
            $InstallPath = $installKey.GetValue("InstallLocation")
            
            if ($InstallPath -and (Test-Path $InstallPath)) {
                Log "  Deleting old folder: $InstallPath"
                cmd /c "rmdir /s /q `"$InstallPath`"" 2>&1 | Out-Null
                Log "  Folder deleted"
            } else {
                Log "  No folder to delete"
            }
        } catch {
            Log "  WARNING: Folder delete failed - $($_.Exception.Message)"
        }

        try {
            Log "  Cleaning registry..."
            $regCommands = @(
                "reg delete `"HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode`" /f",
                "reg delete `"HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode`" /f",
                "reg delete `"HKLM\Software\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$ProductCode`" /f"
            )

            foreach ($cmd in $regCommands) {
                try {
                    cmd /c $cmd 2>&1 | Out-Null
                } catch {
                }
            }
            Log "  Registry cleaned"
        } catch {
            Log "  WARNING: Registry clean failed - $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 1

        Log "  Installing new version..."
        try {
            $install = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MSIPath`" /qn /norestart REINSTALLMODE=vomus /L*v `"C:\temp\SC_MSI_Log.txt`"" -PassThru -Wait
            Log "  Install exit code: $($install.ExitCode)"

            if ($install.ExitCode -eq 0 -or $install.ExitCode -eq 3010) {
                Log "  Installation successful"
            } else {
                Log "  WARNING: Installation exit code $($install.ExitCode)"
            }
        } catch {
            Log "  ERROR: Installation failed - $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 2
    }
} else {
    Log "Skipping upgrade - no instances needing upgrade"
}

Log "Starting ScreenConnect services..."
try {
    Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | ForEach-Object {
        if ($_.Status -ne 'Running') {
            Log "  Starting $($_.Name)..."
            Start-Service -Name $_.Name -ErrorAction SilentlyContinue
        }
    }
    Log "Services started"
} catch {
    Log "ERROR during service start: $($_.Exception.Message)"
}

Start-Sleep -Seconds 3

Log "Checking final service status..."
$allServices = Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" }

if ($allServices) {
    if ($allServices -isnot [array]) {
        $allServices = @($allServices)
    }

    foreach ($svc in $allServices) {
        Log "  Service: $($svc.Name) - Status: $($svc.Status)"
    }
    Log "Upgrade complete"
} else {
    Log "WARNING: No ScreenConnect service found"
}

Log "=== Upgrade Complete ==="
Read-Host "Press Enter to close"