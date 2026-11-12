[CmdletBinding()]
param(
    [switch]$Login,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArgs
)

$ErrorActionPreference = 'Stop'
$proxy = 'socks5h://127.0.0.1:18081'

if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 18081 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw 'AI bridge SOCKS tunnel is unavailable on 127.0.0.1:18081. Claude was not started.'
}

foreach ($name in 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'https_proxy', 'http_proxy', 'all_proxy') {
    Set-Item -Path "Env:$name" -Value $proxy
}
foreach ($name in 'NO_PROXY', 'no_proxy') {
    Set-Item -Path "Env:$name" -Value '127.0.0.1,localhost,::1'
}

if ($Login) {
    Write-Warning 'Claude CLI is proxied. OAuth browser traffic is a separate process; use a SOCKS-configured browser for the login page.'
    & claude auth login @ClaudeArgs
} else {
    & claude @ClaudeArgs
}
exit $LASTEXITCODE
