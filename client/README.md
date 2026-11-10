# Client (локальная сторона — ПК)

Всё, что нужно на машине, где работает агент: туннель до моста и конфиг Hermes,
направленный на `127.0.0.1:8801`.

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

1. Установи Hermes (официальный `NousResearch/hermes-agent`).
2. Скопируй `hermes/config.yaml.example` в `profiles/<твой>/config.yaml`.
3. Скопируй `hermes/.env.example` в `profiles/<твой>/.env`.
4. Запускай через `launch.cmd` / `launch.py` — они пиннуют `HERMES_HOME` и
   кладут весь не-loopback трафик на `socks5h://127.0.0.1:18081`.

Ключ в `.env` — заглушка (`bridge-placeholder`): мост всё равно перезаписывает
`Authorization` на сервере. Реальный ключ на клиенте не нужен.
