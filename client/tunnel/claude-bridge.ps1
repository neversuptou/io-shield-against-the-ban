[CmdletBinding()]
param(
    [switch]$Login,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArgs
)

$ErrorActionPreference = 'Stop'
$httpProxy = 'http://127.0.0.1:18082'

if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 18081 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw 'AI bridge SOCKS tunnel is unavailable on 127.0.0.1:18081. Claude was not started.'
}

if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 18082 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    $env:AI_BRIDGE_PAC_FILE = Join-Path $env:LOCALAPPDATA 'AI-Bridge\proxy.pac'
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $python) { $python = 'python' }
    Start-Process -WindowStyle Hidden -FilePath $python -ArgumentList "`"$PSScriptRoot\http_to_socks_proxy.py`""
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 200
        if (Test-NetConnection -ComputerName 127.0.0.1 -Port 18082 -InformationLevel Quiet -WarningAction SilentlyContinue) { break }
    }
    if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 18082 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        throw 'Local HTTP CONNECT bridge did not start on 127.0.0.1:18082. Claude was not started.'
    }
}

# Claude Code supports HTTP(S) proxies, not SOCKS. The local HTTP CONNECT bridge
# forwards those requests into the SSH SOCKS tunnel without resolving provider DNS locally.
foreach ($name in 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'https_proxy', 'http_proxy', 'all_proxy') {
    Set-Item -Path "Env:$name" -Value $httpProxy
}
foreach ($name in 'NO_PROXY', 'no_proxy') {
    Set-Item -Path "Env:$name" -Value '127.0.0.1,localhost,::1'
}
$env:CLAUDE_CODE_PROXY_RESOLVES_HOSTS = '1'
Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

if ($Login) {
    Write-Warning 'Claude CLI is proxied. OAuth browser traffic is a separate process; use a SOCKS-configured browser for the login page.'
    & claude auth login @ClaudeArgs
} else {
    & claude @ClaudeArgs
}
exit $LASTEXITCODE
