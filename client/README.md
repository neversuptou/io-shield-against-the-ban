# Client (локальная сторона — ПК)

Всё, что нужно на машине, где работает агент: туннель до моста и конфиг Hermes,
направленный на `127.0.0.1:8801`.

## Порядок установки (с нуля)

1. Установи Hermes (официальный `NousResearch/hermes-agent`). Определи его
   **проектный home** — папку, где лежат `hermes-agent/` (исходники) и
   `profiles/`. Ниже зовём её `<HERMES_HOME>`.
2. Положи конфиг и ключ профиля (раздел «Настройка Hermes»).
3. Подними туннель (раздел «Настройка туннеля»).
4. Запусти Hermes через `launch.cmd` / `launch.py`.

## Что внутри

| Путь | Что это |
|---|---|
| `tunnel/tunnel.ps1` | Windows: туннель, привязанный к жизни Hermes (авто up/down) |
| `tunnel/tunnel-forward.sh` | Linux/macOS: простой forward-туннель |
| `tunnel/tunnel-reverse.sh` | Reverse-вариант (сервер сам звонит на ПК) |
| `tunnel/ssh-config.example` | `~/.ssh/config` для forward-модели |
| `tunnel/firewall-killswitch.ps1` | блокирует прямой outbound-443 к провайдерам |
| `tunnel/tunnel-watchdog.ps1` | включает/выключает kill-switch по состоянию туннеля |
| `tunnel/setup-tunnel-task.cmd` | регистрирует скрытую задачу `AI-Bridge-Tunnel` |
| `hermes/config.yaml.example` | конфиг профиля Hermes (провайдер → мост) |
| `hermes/.env.example` | ключ-заглушка для Hermes |
| `hermes/launch.py` + `launch.cmd` | запуск Hermes с SOCKS-маршрутизацией через мост |
| `plugin/ai-quota/plugin.js` | desktop-плагин квот (забирает `/quota/*` с моста) |

## Настройка туннеля

Туннель поднимает на ПК два порта:

- `127.0.0.1:8801` — сам мост (`ssh -L 8801:127.0.0.1:8801`);
- `127.0.0.1:18081` — SOCKS-прокси через сервер (`ssh -D 18081`), через него
  Hermes ходит за веб-инструментами и фоновыми проверками.

Сервер при этом должен принимать SSH (sshd запущен, порт 22 доступен с клиента).

### Вариант A — forward (рекомендуется, как в этой репе)

ПК сам звонит на сервер. Ключ лежит на ПК, на сервер уходит только `.pub`.

```bash
# 1. сгенерировать ключ на ПК:
ssh-keygen -t ed25519 -f ~/.ssh/io-ai-bridge -N ''

# 2. на сервере добавить публичный ключ:
echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys

# 3. поднять туннель:
IO_BRIDGE_HOST=<ip-сервера> ./tunnel/tunnel-forward.sh        # Linux/macOS
#   или настроить env и зарегистрировать задачу на Windows:
setx IO_BRIDGE_HOST <ip-сервера> /M
tunnel\setup-tunnel-task.cmd
```

### Вариант B — reverse (когда до ПК можно достучаться с сервера)

Сервер сам звонит на ПК и открывает `8801` на его loopback. Ключ — на сервере.

```bash
# на сервере:
ssh-keygen -t ed25519 -f /opt/ai-bridge/id_ed25519 -N ''
# добавить его .pub в ~/.ssh/authorized_keys ПК
IO_CLIENT_HOST=<ip-пк> ./tunnel-reverse.sh
```

> Reverse даёт только порт `8801`. SOCKS (`-D 18081`) — свойство forward-модели,
> поэтому маршрутизация веб-трафика Hermes через мост работает только в варианте A.

## Настройка Hermes

Скопируй примеры в профиль:

- `hermes/config.yaml.example` → `<HERMES_HOME>/profiles/<твой>/config.yaml`
- `hermes/.env.example` → `<HERMES_HOME>/profiles/<твой>/.env`

Ключ в `.env` — заглушка (`bridge-placeholder`): мост перезаписывает
`Authorization` на сервере, реальный ключ на клиенте не нужен.

### Плагин квот (опционально)

- `plugin/ai-quota/plugin.js` → `<HERMES_HOME>/desktop-plugins/ai-quota/plugin.js`

Он забирает `/quota/*` с моста и показывает расход квот в дашборде.

## Запуск

`launch.cmd` / `launch.py` пиннуют `HERMES_HOME` и кладут весь не-loopback трафик
на `socks5h://127.0.0.1:18081`. Перед первым запуском задай в `launch.cmd`:

- `IO_HOME` — твой `<HERMES_HOME>` (папка с `hermes-agent/` и `profiles/`);
- `PY` — путь к python (или оставь `python`, если он в PATH).
