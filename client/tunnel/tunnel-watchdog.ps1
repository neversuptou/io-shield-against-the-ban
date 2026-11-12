# Killswitch watchdog — ties the AI-provider direct-block to the Hermes lifecycle:
#   Hermes RUNNING -> block direct outbound 443 to AI providers (always, so no tool
#                     can bypass the bridge and leak the home IP).
#   Hermes CLOSED  -> lift the block (direct provider use works again).
# Runs hidden + elevated (AI-Bridge-Watchdog task, ONLOGON). Re-resolves IPs every 15 min.
$ErrorActionPreference = 'SilentlyContinue'
$rule = 'AI-Bridge-Block-Direct'
$quicRule = 'AI-Bridge-Block-QUIC'
$domains = & "$PSScriptRoot\provider-domains.ps1"
$lastState = $null
$lastResolve = [datetime]::MinValue
$claudeMarker = Join-Path $PSScriptRoot 'claude-bridge.active'

while ($true) {
    $running = [bool](Get-Process Hermes -ErrorAction SilentlyContinue) -or [bool](Get-Process claude -ErrorAction SilentlyContinue)

    if ($running) {
        $stale = $lastResolve -lt (Get-Date).AddMinutes(-15)
        if ($running -ne $lastState -or $stale) {
            $ips = foreach ($d in $domains) {
                try { [System.Net.Dns]::GetHostAddresses($d) |
                    Select-Object -ExpandProperty IPAddressToString } catch {}
            }
            $ips = $ips | Sort-Object -Unique
            if ($ips) {
                Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
                New-NetFirewallRule -DisplayName $rule -Direction Outbound -Action Block `
                  -Protocol TCP -RemotePort 443 -RemoteAddress $ips | Out-Null
                $lastResolve = Get-Date
                Write-Host "$(Get-Date -Format s) hermes running -> block ENABLED ($($ips -join ','))"
            }
        }
        # QUIC (HTTP/3) runs over UDP 443 and would bypass the HTTP proxy; force
        # the browser to fall back to TCP HTTP/2, which routes through the bridge.
        if ((Get-NetFirewallRule -DisplayName $quicRule -ErrorAction SilentlyContinue).Enabled -ne 'True') {
            Remove-NetFirewallRule -DisplayName $quicRule -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName $quicRule -Direction Outbound -Action Block `
              -Protocol UDP -RemotePort 443 | Out-Null
            Write-Host "$(Get-Date -Format s) QUIC block ENABLED"
        }
    } elseif ($running -ne $lastState) {
        Set-NetFirewallRule -DisplayName $rule -Enabled False -ErrorAction SilentlyContinue
        Set-NetFirewallRule -DisplayName $quicRule -Enabled False -ErrorAction SilentlyContinue
        Write-Host "$(Get-Date -Format s) hermes closed -> block DISABLED"
    }

    $lastState = $running
    Start-Sleep -Seconds 5
}
