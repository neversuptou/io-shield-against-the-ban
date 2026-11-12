# AI bridge tunnel, lifecycle tied to protected clients (Hermes, Claude):
#   protected running -> tunnel up   (ssh: 8801 bridge + 18081 SOCKS)
#   protected closed  -> our ssh torn down (only OUR instances, by key path)
# Hidden by design - run via the AI-Bridge-Tunnel scheduled task (ONLOGON).
# Server host and SSH key come from bridge.env (gitignored), not from this file.
$ErrorActionPreference = 'SilentlyContinue'

# Load KEY=VALUE pairs from bridge.env next to this script, if present.
$envFile = Join-Path $PSScriptRoot 'bridge.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=\s]+)\s*=\s*(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim(), 'Process')
        }
    }
}

$log = Join-Path $PSScriptRoot 'tunnel.log'
$key = $env:IO_BRIDGE_KEY
$target = $env:IO_BRIDGE_SSH
if (-not $key -or -not $target) {
    Add-Content $log "$(Get-Date -Format s) missing IO_BRIDGE_KEY / IO_BRIDGE_SSH - set them in bridge.env next to this script"
    exit 1
}

$keyName = Split-Path -Leaf $key
$sshArgs = '-i',$key,
           '-o','StrictHostKeyChecking=no',
           '-o','ServerAliveInterval=15',
           '-o','ServerAliveCountMax=3',
           '-o','ExitOnForwardFailure=yes',
           '-N','-L','8801:127.0.0.1:8801','-D','18081',
           '-E',$log,
           $target

# Our ssh instances are identifiable: command line contains our key path.
$ours = { Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
          Where-Object { ([string]$_.CommandLine) -like "*$keyName*" } }

# The isolated Claude runner runs in a Docker container, so there is no host
# claude.exe process; detect the gateway container instead.
$claudeContainerUp = { (docker ps -q --filter name=io-claude-gateway 2>$null) }

while ($true) {
    $protectedRunning = [bool](Get-Process Hermes -ErrorAction SilentlyContinue) -or
                        [bool](Get-Process claude -ErrorAction SilentlyContinue) -or
                        [bool](& $claudeContainerUp)
    $tunnelUp = Test-NetConnection -ComputerName 127.0.0.1 -Port 8801 -InformationLevel Quiet -WarningAction SilentlyContinue

    if ($protectedRunning -and -not $tunnelUp) {
        Add-Content $log "$(Get-Date -Format s) protected client running, tunnel down -> start"
        Start-Process -WindowStyle Hidden -FilePath "$env:SystemRoot\System32\OpenSSH\ssh.exe" -ArgumentList $sshArgs
        Start-Sleep -Seconds 8
    }
    elseif (-not $protectedRunning -and (& $ours)) {
        Add-Content $log "$(Get-Date -Format s) protected clients closed -> tearing down our ssh"
        & $ours | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 5
    }
    elseif ($protectedRunning -and $tunnelUp -and (& $ours | Measure-Object).Count -gt 1) {
        # dedupe: keep the oldest instance, kill the rest
        (& $ours | Sort-Object CreationDate | Select-Object -Skip 1) |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Seconds 5
}
