# Forward tunnel, lifecycle tied to Hermes:
#   Hermes running -> tunnel up   (ssh: 8801 bridge + 18081 SOCKS)
#   Hermes closed  -> our ssh torn down (only OUR instances, matched by key path)
# Configure via env (IO_BRIDGE_HOST / IO_BRIDGE_USER / IO_BRIDGE_KEY / IO_BRIDGE_LOG)
# or edit the defaults below. Register with setup-tunnel-task.cmd.
$ErrorActionPreference = 'SilentlyContinue'
$server = if ($env:IO_BRIDGE_HOST) { $env:IO_BRIDGE_HOST } else { 'CHANGE-ME-SERVER' }
$user   = if ($env:IO_BRIDGE_USER) { $env:IO_BRIDGE_USER } else { 'root' }
$key    = if ($env:IO_BRIDGE_KEY)  { $env:IO_BRIDGE_KEY }  else { "$env:USERPROFILE\.ssh\io-ai-bridge" }
$log    = if ($env:IO_BRIDGE_LOG)  { $env:IO_BRIDGE_LOG }  else { "$env:TEMP\ai-bridge-tunnel.log" }

$sshArgs = '-i',$key,
           '-o','StrictHostKeyChecking=accept-new',
           '-o','ServerAliveInterval=15',
           '-o','ServerAliveCountMax=3',
           '-o','ExitOnForwardFailure=yes',
           '-N','-L','8801:127.0.0.1:8801','-D','18081',
           '-E',$log,
           "$user@$server"

# Our ssh instances are identifiable: command line contains our key path.
$ours = { Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
          Where-Object { ([string]$_.CommandLine) -like "*$key*" } }

while ($true) {
    $protectedRunning = [bool](Get-Process Hermes -ErrorAction SilentlyContinue) -or [bool](Get-Process claude -ErrorAction SilentlyContinue)
    $tunnelUp = Test-NetConnection -ComputerName 127.0.0.1 -Port 8801 -InformationLevel Quiet -WarningAction SilentlyContinue

    if ($protectedRunning -and -not $tunnelUp) {
        Add-Content $log "$(Get-Date -Format s) hermes running, tunnel down -> start"
        Start-Process -WindowStyle Hidden -FilePath "$env:SystemRoot\System32\OpenSSH\ssh.exe" -ArgumentList $sshArgs
        Start-Sleep -Seconds 8
    }
    elseif (-not $protectedRunning -and (& $ours)) {
        Add-Content $log "$(Get-Date -Format s) hermes closed -> tearing down our ssh"
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
