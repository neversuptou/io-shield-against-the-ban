#!/bin/sh
set -eu

SOCKS_HOST="${SOCKS_HOST:-host.docker.internal}"
SOCKS_PORT="${SOCKS_PORT:-18081}"
PROXY_IP="$(getent hosts "$SOCKS_HOST" | awk 'NR==1 {print $1}')"
if [ -z "$PROXY_IP" ]; then
  echo "Cannot resolve SOCKS host: $SOCKS_HOST" >&2
  exit 1
fi

export SOCKS_HOST SOCKS_PORT
envsubst < /etc/redsocks.conf.template > /etc/redsocks.conf

# Only this network namespace is modified. The Claude runner joins it with
# --network container:io-claude-gateway; nothing is changed on the Windows host.
iptables -t nat -N IO_CLAUDE_REDSOCKS 2>/dev/null || true
iptables -t nat -F IO_CLAUDE_REDSOCKS
iptables -t nat -A IO_CLAUDE_REDSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A IO_CLAUDE_REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A IO_CLAUDE_REDSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A IO_CLAUDE_REDSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A IO_CLAUDE_REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A IO_CLAUDE_REDSOCKS -d "$PROXY_IP" -j RETURN
iptables -t nat -A IO_CLAUDE_REDSOCKS -p tcp -j REDIRECT --to-ports 12345
iptables -t nat -C OUTPUT -j IO_CLAUDE_REDSOCKS 2>/dev/null || iptables -t nat -A OUTPUT -j IO_CLAUDE_REDSOCKS

# Claude and its plugins have no legitimate UDP requirement. Block QUIC,
# WebRTC/STUN, and direct DNS from the isolated namespace.
iptables -C OUTPUT -p udp -j REJECT 2>/dev/null || iptables -A OUTPUT -p udp -j REJECT

exec redsocks -c /etc/redsocks.conf
