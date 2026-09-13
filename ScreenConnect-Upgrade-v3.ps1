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

# Get product codes from registry
$productCodes = @()
$regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
if (Test-Path $regPath) {
    Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.GetValue("DisplayName") -like "*ScreenConnect*") {
            $productCodes += @{
                Code = (Split-Path -Leaf $_.PSPath)
                Name = $_.GetValue("DisplayName")
            }
        }
    }
}

Log "Found $($productCodes.Count) ScreenConnect installations"

# AGGRESSIVE registry cleanup
foreach ($product in $productCodes) {
    Log "Cleaning all registry for: $($product.Name)"
    
    # Delete from all possible registry locations
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($product.Code)",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($product.Code)",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$($product.Code)",
        "HKLM:\Software\ScreenConnect"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            Log "  Deleted: $path"
        }
    }
}

# Download MSI
if (!(Test-Path $MSIPath)) {
    Log "Downloading MSI..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $GitHubURL -OutFile $MSIPath -ErrorAction Stop
    Log "Download complete"
}

# Stop services
Log "Stopping services..."
Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | Where-Object { $_.Status -eq 'Running' } | ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# Install
Log "Installing ScreenConnect v26.6.5.9742..."
$install = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MSIPath`" /qn /norestart /L*v `"C:\temp\SC_MSI_Log.txt`"" -PassThru -Wait
Log "Install exit code: $($install.ExitCode)"

Start-Sleep -Seconds 2

# Start services
Log "Starting services..."
Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | ForEach-Object {
    Start-Service -Name $_.Name -ErrorAction SilentlyContinue
}

Log "=== Complete ==="
Read-Host "Press Enter"