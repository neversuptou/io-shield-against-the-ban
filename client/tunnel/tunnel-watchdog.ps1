# Killswitch watchdog — ties the AI-provider direct-block to the Hermes lifecycle:
#   Hermes RUNNING -> block direct outbound 443 to AI providers (always, so no tool
#                     can bypass the bridge and leak the home IP).
#   Hermes CLOSED  -> lift the block (direct provider use works again).
# Runs hidden + elevated (AI-Bridge-Watchdog task, ONLOGON). Re-resolves IPs every 15 min.
$ErrorActionPreference = 'SilentlyContinue'
$rule = 'AI-Bridge-Block-Direct'
$domains = 'api.z.ai', 'zcode.z.ai', 'api.anthropic.com', 'sentry.io'
$lastState = $null
$lastResolve = [datetime]::MinValue

while ($true) {
    $running = [bool](Get-Process Hermes -ErrorAction SilentlyContinue)

    if ($running) {
        $stale = $lastResolve -lt (Get-Date).AddMinutes(-15)
        if ($running -ne $lastState -or $stale) {
            $ips = foreach ($d in $domains) {
                try { [System.Net.Dns]::GetHostAddresses($d) |
                    Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
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
    } elseif ($running -ne $lastState) {
        Set-NetFirewallRule -DisplayName $rule -Enabled False -ErrorAction SilentlyContinue
        Write-Host "$(Get-Date -Format s) hermes closed -> block DISABLED"
    }

    $lastState = $running
    Start-Sleep -Seconds 5
}
