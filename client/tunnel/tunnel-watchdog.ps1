# Tunnel watchdog: when the AI bridge tunnel is DOWN, enable the firewall
# block so no app can reach AI providers directly (requests fail instead of
# leaking). When the tunnel is UP, keep the block disabled.
# Runs as a hidden elevated background task (registered by setup script).
$ErrorActionPreference = 'ContinuallySilently'
$rule = 'AI-Bridge-Block-Direct'
$domains = 'api.z.ai', 'zcode.z.ai', 'api.anthropic.com', 'sentry.io'
$lastState = $null

while ($true) {
    $up = Test-NetConnection -ComputerName 127.0.0.1 -Port 18081 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($up -ne $lastState) {
        if ($up) {
            Set-NetFirewallRule -DisplayName $rule -Enabled False -ErrorAction SilentlyContinue
            Write-Host "$(Get-Date -Format s) tunnel UP -> block disabled"
        } else {
            # (Re)resolve provider IPs so the block stays current, then enable.
            $ips = foreach ($d in $domains) {
                try { [System.Net.Dns]::GetHostAddresses($d) |
                    Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                    Select-Object -ExpandProperty IPAddressToString } catch {}
            }
            $ips = $ips | Sort-Object -Unique
            Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName $rule -Direction Outbound -Action Block `
              -Protocol TCP -RemotePort 443 -RemoteAddress $ips | Out-Null
            Write-Host "$(Get-Date -Format s) tunnel DOWN -> block ENABLED ($($ips -join ','))"
        }
        $lastState = $up
    }
    Start-Sleep -Seconds 5
}
