#!/usr/bin/env bash
# Deploy the AI bridge to a fresh Ubuntu/Debian server.
# Run as root on the server, from this directory:
#   ZAI_KEY=sk-... OPENAI_TOKEN=... ./deploy.sh
# Alternatively pre-place the secrets in ./zai-key and ./openai-token.
# OPENAI_TOKEN is optional — only needed for the /quota/openai route.
set -euo pipefail

ZAI_KEY="${ZAI_KEY:-$(cat zai-key 2>/dev/null || true)}"
OPENAI_TOKEN="${OPENAI_TOKEN:-$(cat openai-token 2>/dev/null || true)}"
if [ -z "${ZAI_KEY}" ]; then
  echo "usage: ZAI_KEY=<z.ai key> [OPENAI_TOKEN=<chatgpt token>] ./deploy.sh" >&2
  exit 1
fi

if ! command -v caddy >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update -qq && apt-get install -y -qq caddy
fi

mkdir -p /opt/ai-bridge
for f in Caddyfile ai-bridge.service; do
  if [ "$(readlink -f "$f")" != "$(readlink -f "/opt/ai-bridge/$f")" ]; then
    install -m 644 "$f" "/opt/ai-bridge/$f"
  fi
done
umask 077
{
  printf 'ZAI_KEY=%s\n' "$ZAI_KEY"
  [ -n "$OPENAI_TOKEN" ] && printf 'OPENAI_TOKEN=%s\n' "$OPENAI_TOKEN"
} > /opt/ai-bridge/env
install -m 644 ai-bridge.service /etc/systemd/system/ai-bridge.service
systemctl daemon-reload
systemctl enable --now ai-bridge
sleep 1
systemctl is-active ai-bridge

# Smoke test: an unauthenticated probe must still reach the provider (401/429).
curl -s -m 15 http://127.0.0.1:8801/zai/anthropic/v1/messages \
  -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"glm-5.3-flash","max_tokens":8,"messages":[{"role":"user","content":"hi"}]}' | head -c 200
echo
echo "ai-bridge deployed. Port 127.0.0.1:8801, loopback only."
