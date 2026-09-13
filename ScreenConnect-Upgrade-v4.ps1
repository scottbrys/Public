# ScreenConnect Upgrade v4 - Aggressive detection and cleanup
$ErrorActionPreference = "SilentlyContinue"

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === ScreenConnect Upgrade Started ==="

# Find all ScreenConnect product codes from all locations
$productCodes = @()

# Check HKLM 64-bit
$productCodes += Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | 
    Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'} | 
    ForEach-Object {$_.PSChildName}

# Check HKLM 32-bit (Wow6432Node)
$productCodes += Get-ChildItem 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | 
    Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'} | 
    ForEach-Object {$_.PSChildName}

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Found $($productCodes.Count) ScreenConnect installations"
$productCodes | ForEach-Object { Write-Host "  - $_" }

# Stop all ScreenConnect services
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Stopping ScreenConnect services..."
Get-Service | Where-Object {$_.Name -like '*ScreenConnect*'} | Stop-Service -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Uninstall all found versions with msiexec
$productCodes | ForEach-Object {
    $code = $_
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Uninstalling $code..."
    $result = & msiexec.exe /X $code /qn /norestart
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Uninstall exit code: $result"
    Start-Sleep -Seconds 2
}

# Clean ScreenConnect registry paths
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Cleaning registry..."
Remove-Item 'HKLM:\Software\ScreenConnect' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\Software\Wow6432Node\ScreenConnect' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Downloading ScreenConnect v26.6.5.9742..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/scottbrys/Public/main/ScreenConnect.ClientSetup.msi', 'C:\Temp\ScreenConnect.ClientSetup.msi')

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Installing ScreenConnect v26.6.5.9742..."
$result = & msiexec.exe /I C:\Temp\ScreenConnect.ClientSetup.msi /qn /norestart
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Install exit code: $result"

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting ScreenConnect services..."
Get-Service | Where-Object {$_.Name -like '*ScreenConnect*'} | Start-Service -ErrorAction SilentlyContinue

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === Complete ==="
Read-Host "Press Enter"