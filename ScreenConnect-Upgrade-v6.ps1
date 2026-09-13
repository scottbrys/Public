$ErrorActionPreference = "SilentlyContinue"
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === ScreenConnect Upgrade v6 Started ==="

# Search ALL possible registry locations for ScreenConnect
$toDelete = @()

# Standard Uninstall paths
$toDelete += Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'}
$toDelete += Get-ChildItem 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | Where-Object {$_.GetValue('DisplayName') -like '*ScreenConnect*'}

# Non-standard: Classes\Installer\Products
$toDelete += Get-ChildItem 'HKLM:\Software\Classes\Installer\Products' | Where-Object {(Get-ItemProperty $_.PSPath).ProductName -like '*ScreenConnect*'}

# URL Scheme keys
$toDelete += Get-ChildItem 'HKLM:\Software\Classes' | Where-Object {$_.PSChildName -like 'sc-*'}

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Found $($toDelete.Count) ScreenConnect entries to remove"

# Stop services
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Stopping services..."
Get-Service | Where-Object {$_.Name -like '*ScreenConnect*'} | Stop-Service -Force
Start-Sleep -Seconds 2

# Delete each entry
$toDelete | ForEach-Object {
    Write-Host "  Deleting: $($_.PSPath)"
    Remove-Item $_.PSPath -Recurse -Force
}

# Delete folders
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Deleting installation folders..."
Remove-Item 'C:\Program Files (x86)\ScreenConnect*' -Recurse -Force
Remove-Item 'HKLM:\Software\ScreenConnect' -Recurse -Force
Remove-Item 'HKLM:\Software\Wow6432Node\ScreenConnect' -Recurse -Force

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Downloading v26.6.5.9742..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/scottbrys/Public/main/ScreenConnect.ClientSetup.msi', 'C:\Temp\ScreenConnect.ClientSetup.msi')

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Installing..."
$result = & msiexec.exe /I C:\Temp\ScreenConnect.ClientSetup.msi /qn /norestart
Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Exit code: $result"

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting services..."
Start-Sleep 2
Get-Service | Where-Object {$_.Name -like '*ScreenConnect*'} | Start-Service

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === Complete ==="
