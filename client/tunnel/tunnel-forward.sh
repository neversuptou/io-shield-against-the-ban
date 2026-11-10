# Forward tunnel (PC -> server). Brings the bridge to 127.0.0.1:8801 and a
# SOCKS proxy to 127.0.0.1:18081 on this machine.
#
#   IO_BRIDGE_HOST=<ip-or-host> [IO_BRIDGE_USER=root] [IO_BRIDGE_KEY=~/.ssh/io-ai-bridge] ./tunnel-forward.sh
#
# Keep it alive with a supervisor (systemd user unit / launchd / autossh), e.g.:
#   autossh -M 0 -N -L 8801:127.0.0.1:8801 -D 18081 -i "$KEY" "$USER@$HOST"
set -euo pipefail

HOST="${IO_BRIDGE_HOST:?set IO_BRIDGE_HOST}"
USER="${IO_BRIDGE_USER:-root}"
KEY="${IO_BRIDGE_KEY:-$HOME/.ssh/io-ai-bridge}"

exec ssh -N \
  -i "$KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -L 8801:127.0.0.1:8801 \
  -D 18081 \
  "$USER@$HOST"
