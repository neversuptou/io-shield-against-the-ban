# Enables a scoped Windows proxy only while Hermes is running, so OAuth browsers
# route AI-provider traffic through the SSH SOCKS tunnel WITHOUT hijacking the
# user's internal/corporate network. A PAC file proxies only the provider/OAuth
# domains; private ranges, loopback, link-local and everything else go DIRECT.
# The previous user settings are restored when Hermes exits.
$ErrorActionPreference = 'SilentlyContinue'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$pacDir = Join-Path $env:LOCALAPPDATA 'AI-Bridge'
$pacPath = Join-Path $pacDir 'proxy.pac'
$backupPath = Join-Path $pacDir 'hermes-system-proxy-backup.json'
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

function New-PacFile {
    New-Item -ItemType Directory -Force -Path $pacDir | Out-Null
    $pac = @"
function FindProxyForURL(url, host) {
    host = host.toLowerCase();
    // Internal, loopback, link-local and plain-name hosts are reachable only on
    // the local/corporate network and must never leave through the tunnel.
    if (isPlainHostName(host) ||
        host == "localhost" ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }
    // Everything public goes through the SSH bridge to hide the home IP.
    return "PROXY 127.0.0.1:18082";
}
"@
    [System.IO.File]::WriteAllText($pacPath, $pac, (New-Object System.Text.UTF8Encoding($false)))
    return 'http://127.0.0.1:18082/proxy.pac'
}

function Enable-BridgeProxy {
    if ($enabled) { return }
    $current = Get-ItemProperty -Path $registryPath
    $backup = [ordered]@{}
    foreach ($name in $names) {
        $property = $current.PSObject.Properties[$name]
        $backup[$name] = [ordered]@{ Exists = ($null -ne $property); Value = if ($property) { $property.Value } else { $null } }
    }
    New-Item -ItemType Directory -Force -Path $pacDir | Out-Null
    $backup | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 -Path $backupPath
    $pacUrl = New-PacFile
    New-ItemProperty -Path $registryPath -Name 'ProxyEnable' -PropertyType DWord -Value 1 -Force | Out-Null
    Remove-ItemProperty -Path $registryPath -Name 'ProxyServer' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $registryPath -Name 'ProxyOverride' -ErrorAction SilentlyContinue
    New-ItemProperty -Path $registryPath -Name 'AutoConfigURL' -Value $pacUrl -Force | Out-Null
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
