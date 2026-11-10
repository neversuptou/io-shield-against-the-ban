# AI bridge (серверная часть)

Caddy-прокси на порту `8801`, **только loopback** — снаружи доступен лишь через
SSH-туннель. Реальные ключи провайдеров живут на сервере в
`/opt/ai-bridge/env` (chmod 600) и подставляются в заголовок `Authorization`
на каждый запрос. Клиент держит заглушку и своего ключа вообще не имеет.

## Маршруты

| Клиентский путь | Куда идёт | Кто ходит |
|---|---|---|
| `/zai/anthropic/*` | `api.z.ai` (Anthropic wire) | claude CLI |
| `/zai/paas/*` | `api.z.ai/api/paas/v4` (OpenAI wire) | Hermes |
| `/anthropic/*` | `api.anthropic.com/v1` | claude CLI |
| `/quota/zai` | `api.z.ai` quota limit | `ai-quota` plugin |
| `/quota/zai-week` | `api.z.ai` model usage | `ai-quota` plugin |
| `/quota/openai` | `chatgpt.com` usage | `ai-quota` plugin |

## Развёртывание (Ubuntu/Debian, root)

```bash
# на сервере, из этой папки:
ZAI_KEY=sk-ваш-ключ OPENAI_TOKEN=... ./deploy.sh

# затем добавить публичный ключ клиента (для туннеля):
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys
```

`deploy.sh` сам ставит Caddy, раскладывает `Caddyfile` и `ai-bridge.service`,
пишет `/opt/ai-bridge/env` (ZAI_KEY + опц. OPENAI_TOKEN), включает systemd-юнит
и гоняет smoke-тест.

## Что НЕ класть в git

`env`, `zai-key`, `openai-token`, любые приватные SSH-ключи. Пример — `.env.example`.
