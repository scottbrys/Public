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

Write-Host "Script started" -ForegroundColor Green
Log "=== ScreenConnect Upgrade Started ==="

if (-not (Test-Path "C:\temp")) {
    New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
}

try {
    Log "Step 1: Detecting ScreenConnect..."
    $instancesToUpgrade = @()
    
    $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    if (Test-Path $regPath) {
        $keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $displayName = $key.GetValue("DisplayName")
            $displayVersion = $key.GetValue("DisplayVersion")
            
            if ($displayName -like "*ScreenConnect*") {
                $productCode = Split-Path -Leaf $key.PSPath
                Log "Found: $displayName v$displayVersion"
                
                if ($displayVersion -ne "26.6.5.9742") {
                    Log "Status: Needs upgrade"
                    $instancesToUpgrade += @{
                        Name = $displayName
                        Version = $displayVersion
                        ProductCode = $productCode
                        RegistryPath = $key.PSPath
                    }
                } else {
                    Log "Status: Already latest version"
                }
            }
        }
    }
    
    Log "Instances to upgrade: $($instancesToUpgrade.Count)"
    
    if ($instancesToUpgrade.Count -eq 0) {
        Log "No upgrade needed"
    } else {
        Log "Step 2: Downloading MSI..."
        if (!(Test-Path $MSIPath)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $GitHubURL -OutFile $MSIPath -ErrorAction Stop
            Log "MSI downloaded"
        } else {
            Log "MSI already exists"
        }
        
        Log "Step 3: Stopping services..."
        Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | Where-Object { $_.Status -eq 'Running' } | ForEach-Object {
            Log "Stopping: $($_.Name)"
            Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
        Log "Services stopped"
        Start-Sleep -Seconds 2
        
        foreach ($product in $instancesToUpgrade) {
            Log "Step 4: Upgrading $($product.Name)..."
            
            $installKey = Get-Item -Path $product.RegistryPath -ErrorAction SilentlyContinue
            $InstallPath = $installKey.GetValue("InstallLocation")
            
            if ($InstallPath -and (Test-Path $InstallPath)) {
                Log "Deleting: $InstallPath"
                cmd /c "rmdir /s /q `"$InstallPath`"" 2>&1 | Out-Null
            }
            
            Log "Cleaning registry..."
            cmd /c "reg delete `"HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($product.ProductCode)`" /f" 2>&1 | Out-Null
            cmd /c "reg delete `"HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($product.ProductCode)`" /f" 2>&1 | Out-Null
            
            Log "Installing new version..."
            $install = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MSIPath`" /qn /norestart REINSTALLMODE=vomus /L*v `"C:\temp\SC_MSI_Log.txt`"" -PassThru -Wait
            Log "Install exit code: $($install.ExitCode)"
            
            Start-Sleep -Seconds 2
        }
        
        Log "Step 5: Starting services..."
        Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" } | ForEach-Object {
            if ($_.Status -ne 'Running') {
                Log "Starting: $($_.Name)"
                Start-Service -Name $_.Name -ErrorAction SilentlyContinue
            }
        }
        
        Log "COMPLETE"
    }
} catch {
    Log "ERROR: $($_.Exception.Message)"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Done - Press Enter to close" -ForegroundColor Green
Read-Host