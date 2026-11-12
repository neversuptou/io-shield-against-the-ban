[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ClaudeArgs)

$ErrorActionPreference = 'Stop'
# Single source of truth for the Claude Code version (keep in sync with the
# Dockerfile ARG default; this value is passed as --build-arg and used as tag).
$claudeVersion = '2.1.319'
$compose = Join-Path $PSScriptRoot 'claude-container\compose.yaml'
if (-not (Test-Path -LiteralPath $compose)) {
    $compose = Join-Path (Split-Path -Parent $PSScriptRoot) 'claude-container\compose.yaml'
}
$workspace = (Get-Location).Path

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop CLI is not available.' }
if (-not (Test-NetConnection 127.0.0.1 -Port 18081 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw 'AI bridge SOCKS tunnel is unavailable; Claude container will not start.'
}

$hostProxyIp = ((& docker run --rm --entrypoint getent alpine:3.21.3 hosts host.docker.internal) -split '\s+')[0]
if ([string]::IsNullOrWhiteSpace($hostProxyIp)) { throw 'Docker Desktop host address is unavailable.' }
$previousSocksHost = $env:SOCKS_HOST
$env:SOCKS_HOST = $hostProxyIp
try {
    & docker compose -f $compose up -d --force-recreate gateway
    if ($LASTEXITCODE -ne 0) { throw 'Unable to start the isolated Claude gateway.' }
} finally {
    $env:SOCKS_HOST = $previousSocksHost
}
if (-not (& docker image inspect io-claude-runner:$claudeVersion 2>$null)) {
    $env:CLAUDE_CODE_VERSION = $claudeVersion
    & docker compose -f $compose --profile build-only build --build-arg CLAUDE_CODE_VERSION=$claudeVersion runner
    if ($LASTEXITCODE -ne 0) { throw 'Unable to build the isolated Claude runner.' }
}

$interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
$dockerArgs = @('run', '--rm')
if ($interactive) { $dockerArgs += '-it' }
$proxyBase = "http://${hostProxyIp}:18082"
$dockerArgs += @(
    '--network', 'container:io-claude-gateway',
    '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
    '--pids-limit', '256', '--tmpfs', '/tmp:rw,noexec,nosuid,size=512m',
    '--mount', 'type=volume,src=io-claude-state,dst=/home/claude',
    '--mount', "type=bind,src=$workspace,dst=/workspace",
    '--workdir', '/workspace',
    '--env', "HTTP_PROXY=$proxyBase",
    '--env', "HTTPS_PROXY=$proxyBase",
    '--env', "ALL_PROXY=$proxyBase",
    '--env', "http_proxy=$proxyBase",
    '--env', "https_proxy=$proxyBase",
    '--env', "all_proxy=$proxyBase",
    '--env', 'NO_PROXY=localhost,127.0.0.1,::1',
    '--env', 'no_proxy=localhost,127.0.0.1,::1',
    "io-claude-runner:$claudeVersion"
) + $ClaudeArgs
& docker @dockerArgs
exit $LASTEXITCODE
