# AI bridge kill-switch: block direct outbound 443 to AI providers from this
# machine. Only the SSH tunnel process may reach them (its traffic leaves via
# the server, where the bridge proxy connects instead).
# Run as Administrator. Re-run after provider IP changes (script re-resolves).
$ErrorActionPreference = 'Stop'
$domains = & "$PSScriptRoot\provider-domains.ps1"
$ips = foreach ($d in $domains) {
  try { [System.Net.Dns]::GetHostAddresses($d) | Select-Object -ExpandProperty IPAddressToString } catch {}
}
$ips = $ips | Sort-Object -Unique
Write-Host "Blocking: $($ips -join ', ')"

$rule = 'AI-Bridge-Block-Direct'
Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $rule -Direction Outbound -Action Block `
  -Protocol TCP -RemotePort 443 -RemoteAddress $ips | Out-Null
# Allow the tunnel itself (ssh.exe) — create explicit allow with higher priority.
$allow = 'AI-Bridge-Allow-SSH'
Remove-NetFirewallRule -DisplayName $allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $allow -Direction Outbound -Action Allow `
  -Protocol TCP -RemotePort 443,22 -Program "$env:SystemRoot\System32\OpenSSH\ssh.exe" | Out-Null
Get-NetFirewallRule -DisplayName 'AI-Bridge-*' | Format-Table DisplayName, Enabled, Action -AutoSize
