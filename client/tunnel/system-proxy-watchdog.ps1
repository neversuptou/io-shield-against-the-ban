# Enables the Windows user proxy only while Hermes is running, so OAuth browsers
# follow the same SSH SOCKS tunnel. The previous user settings are restored when
# Hermes exits.
$ErrorActionPreference = 'SilentlyContinue'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$backupPath = Join-Path $env:LOCALAPPDATA 'AI-Bridge\hermes-system-proxy-backup.json'
$names = 'ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL'
$enabled = $false
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'AI-Bridge-SystemProxy', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Refresh-InternetSettings {
    if (-not ('AiBridge.WinInet' -as [type])) {
        Add-Type @'
using System.Runtime.InteropServices;
namespace AiBridge { public static class WinInet {
  [DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(System.IntPtr hInternet, int option, System.IntPtr buffer, int length);
}}
'@
    }
    [AiBridge.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [AiBridge.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Enable-BridgeProxy {
    if ($enabled) { return }
    $current = Get-ItemProperty -Path $registryPath
    $backup = [ordered]@{}
    foreach ($name in $names) {
        $property = $current.PSObject.Properties[$name]
        $backup[$name] = [ordered]@{ Exists = ($null -ne $property); Value = if ($property) { $property.Value } else { $null } }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
    $backup | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 -Path $backupPath
    New-ItemProperty -Path $registryPath -Name 'ProxyEnable' -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name 'ProxyServer' -Value 'socks=127.0.0.1:18081' -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name 'ProxyOverride' -Value '<local>;127.0.0.1;localhost;::1' -Force | Out-Null
    Remove-ItemProperty -Path $registryPath -Name 'AutoConfigURL' -ErrorAction SilentlyContinue
    Refresh-InternetSettings
    $enabled = $true
}

function Restore-Proxy {
    if (-not (Test-Path $backupPath)) { $enabled = $false; return }
    $backup = Get-Content -Raw -Path $backupPath | ConvertFrom-Json
    foreach ($name in $names) {
        $item = $backup.$name
        if ($item.Exists) { New-ItemProperty -Path $registryPath -Name $name -Value $item.Value -Force | Out-Null }
        else { Remove-ItemProperty -Path $registryPath -Name $name -ErrorAction SilentlyContinue }
    }
    Refresh-InternetSettings
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    $enabled = $false
}

while ($true) {
    $hermesRunning = [bool](Get-Process Hermes -ErrorAction SilentlyContinue)
    if ($hermesRunning) { Enable-BridgeProxy } else { Restore-Proxy }
    Start-Sleep -Seconds 3
}
