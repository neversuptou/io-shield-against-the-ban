#!/usr/bin/env bash
# Reverse tunnel — run ON THE SERVER when the client PC cannot be dialled but
# can itself be reached (public IP / port-forward). Opens 127.0.0.1:8801 on the
# PC, mapping back to the bridge's 8801 on the server. Key lives on the server.
#
#   IO_CLIENT_HOST=<pc-ip> [IO_CLIENT_USER=root] [IO_CLIENT_KEY=/opt/ai-bridge/id_ed25519] ./tunnel-reverse.sh
#
# Requires autossh; keep it alive with a systemd unit, e.g.:
#   autossh -M 0 -N -R 8801:127.0.0.1:8801 -i "$KEY" "$USER@$HOST"
set -euo pipefail

HOST="${IO_CLIENT_HOST:?set IO_CLIENT_HOST}"
USER="${IO_CLIENT_USER:-root}"
KEY="${IO_CLIENT_KEY:-/opt/ai-bridge/id_ed25519}"

# autossh if present, otherwise plain ssh (no auto-restart).
if command -v autossh >/dev/null 2>&1; then
  SSH=autossh
  EXTRA=(-M 0)
else
  SSH=ssh
  EXTRA=()
fi

exec "$SSH" "${EXTRA[@]}" -N \
  -i "$KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R 8801:127.0.0.1:8801 \
  "$USER@$HOST"
