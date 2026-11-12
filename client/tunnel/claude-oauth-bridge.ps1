[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$proxy = 'socks=127.0.0.1:18081'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$backupPath = Join-Path $env:LOCALAPPDATA 'AI-Bridge\claude-oauth-proxy-backup.json'

if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 18081 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw 'AI bridge SOCKS tunnel is unavailable on 127.0.0.1:18081. OAuth was not started.'
}

function Refresh-InternetSettings {
    if (-not ('AiBridge.WinInet' -as [type])) {
        Add-Type @'
using System.Runtime.InteropServices;
namespace AiBridge {
  public static class WinInet {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(System.IntPtr hInternet, int option, System.IntPtr buffer, int length);
  }
}
'@
    }
    [AiBridge.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [AiBridge.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

$names = 'ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL'
$current = Get-ItemProperty -Path $registryPath
$backup = [ordered]@{}
foreach ($name in $names) {
    $property = $current.PSObject.Properties[$name]
    $backup[$name] = [ordered]@{ Exists = ($null -ne $property); Value = if ($property) { $property.Value } else { $null } }
}
New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
$backup | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 -Path $backupPath

function Restore-Proxy {
    foreach ($name in $names) {
        $item = $backup[$name]
        if ($item.Exists) {
            New-ItemProperty -Path $registryPath -Name $name -Value $item.Value -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $registryPath -Name $name -ErrorAction SilentlyContinue
        }
    }
    Refresh-InternetSettings
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
}

try {
    New-ItemProperty -Path $registryPath -Name 'ProxyEnable' -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name 'ProxyServer' -Value $proxy -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name 'ProxyOverride' -Value '<local>;127.0.0.1;localhost;::1' -Force | Out-Null
    Remove-ItemProperty -Path $registryPath -Name 'AutoConfigURL' -ErrorAction SilentlyContinue
    Refresh-InternetSettings

    if ($DryRun) {
        Write-Host 'Temporary system SOCKS proxy applied successfully; restoring it now.' -ForegroundColor Green
    } else {
        Write-Host 'System SOCKS proxy enabled only for this Claude OAuth login.' -ForegroundColor Yellow
        & "$PSScriptRoot\claude-bridge.ps1" -Login
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
    }
} finally {
    Restore-Proxy
    Write-Host 'Previous system proxy settings restored.' -ForegroundColor Green
}
