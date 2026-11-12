[CmdletBinding()]
param(
    [string]$ExpectedEgressIp,
    [string]$HealthUrl = 'http://127.0.0.1:8801/healthz',
    [string]$SocksProxy = 'socks5h://127.0.0.1:18081'
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Test-Check {
    param([string]$Name, [scriptblock]$Check)

    try {
        $result = & $Check
        if ($result) {
            Write-Host "PASS  $Name" -ForegroundColor Green
        } else {
            $failures.Add($Name)
            Write-Host "FAIL  $Name" -ForegroundColor Red
        }
    } catch {
        $failures.Add("${Name}: $($_.Exception.Message)")
        Write-Host "FAIL  ${Name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Test-Check 'SSH forward and Caddy health endpoint' {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 5
    $response.StatusCode -eq 204
}

Test-Check 'SOCKS listener' {
    Test-NetConnection -ComputerName 127.0.0.1 -Port 18081 -InformationLevel Quiet -WarningAction SilentlyContinue
}

if ($ExpectedEgressIp) {
    Test-Check "SOCKS egress IP is $ExpectedEgressIp" {
        $ip = (& curl.exe --silent --show-error --fail --max-time 10 --proxy $SocksProxy https://api.ipify.org).Trim()
        $ip -eq $ExpectedEgressIp
    }
}

$hermesRunning = [bool](Get-Process Hermes -ErrorAction SilentlyContinue)
if ($hermesRunning) {
    Test-Check 'Direct-provider firewall block is enabled while Hermes runs' {
        $rule = Get-NetFirewallRule -DisplayName 'AI-Bridge-Block-Direct' -ErrorAction Stop
        $rule.Enabled -eq 'True' -and $rule.Direction -eq 'Outbound' -and $rule.Action -eq 'Block'
    }
} else {
    Write-Host 'INFO  Hermes is not running; firewall state is not checked.' -ForegroundColor Yellow
}

if ($failures.Count) {
    Write-Error ("AI bridge verification failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'AI bridge verification passed.' -ForegroundColor Green
