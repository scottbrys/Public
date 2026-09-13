# ScreenConnect Upgrade v5 - Clean registry deletion before install
$ErrorActionPreference = "SilentlyContinue"

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === ScreenConnect Upgrade v5 Started ==="

# Find all ScreenConnect product codes
$allProducts = @()
$allProducts += Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | 
    Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'}
$allProducts += Get-ChildItem 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | 
    Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'}

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Found $($allProducts.Count) ScreenConnect installations"

# Stop all ScreenConnect services
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Stopping ScreenConnect services..."
Get-Service | Where-Object {$_.Name -like '*ScreenConnect*'} | Stop-Service -Force
Start-Sleep -Seconds 2

# For each old installation, delete registry and folder
$allProducts | ForEach-Object {
    $regPath = $_.PSPath
    $productCode = $_.PSChildName
    $displayName = $_.GetValue('DisplayName')
    $version = $_.GetValue('DisplayVersion')
    $installPath = $_.GetValue('InstallLocation')
    
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Removing: $displayName (v$version)"
    
    # Delete from registry
    Write-Host "  Deleting registry: $regPath"
    Remove-Item $regPath -Recurse -Force
    
    # Delete installation folder
    if ($installPath -and (Test-Path $installPath)) {
        Write-Host "  Deleting folder: $installPath"
        Remove-Item $installPath -Recurse -Force
    }
    
    # Delete from Installer UserData
    $userDataPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$productCode"
    if (Test-Path $userDataPath) {
        Write-Host "  Deleting UserData: $userDataPath"
        Remove-Item $userDataPath -Recurse -Force
    }
}

# Clean ScreenConnect registry paths
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Cleaning ScreenConnect registry..."
Remove-Item 'HKLM:\Software\ScreenConnect' -Recurse -Force
Remove-Item 'HKLM:\Software\Wow6432Node\ScreenConnect' -Recurse -Force

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Downloading ScreenConnect v26.6.5.9742..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/scottbrys/Public/main/ScreenConnect.ClientSetup.msi', 'C:\Temp\ScreenConnect.ClientSetup.msi')

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Installing ScreenConnect v26.6.5.9742..."
$result = & msiexec.exe /I C:\Temp\ScreenConnect.ClientSetup.msi /qn /norestart
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Install exit code: $result"

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting ScreenConnect services..."
Start-Sleep -Seconds 2
Get-Service | Where-Object {$_.Name -like '*ScreenConnect*'} | Start-Service

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === Complete ==="
Read-Host "Press Enter"