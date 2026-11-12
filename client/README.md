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
| `tunnel/firewall-killswitch.ps1` | блокирует прямой outbound-443 к встроенным провайдерам |
| `tunnel/provider-domains.ps1` | список встроенных provider/OAuth доменов для fail-closed firewall |
| `tunnel/tunnel-watchdog.ps1` | включает/выключает kill-switch по состоянию Hermes; также блокирует QUIC (UDP 443) |
| `tunnel/system-proxy-watchdog.ps1` | PAC-прокси: публичный трафик → туннель, внутренние/частные домены → напрямую, без локального DNS |
| `tunnel/http_to_socks_proxy.py` | loopback-only HTTP CONNECT → SOCKS адаптер + отдаёт PAC на `/proxy.pac` |
| `tunnel/claude-container.ps1` | запускает Claude Code в изолированном Docker-контейнере |
| `claude-container/` | Docker runner + gateway (redsocks + iptables, fail-closed egress) |
| `tunnel/claude-bridge.ps1` | (legacy) Claude CLI через HTTP CONNECT → SSH SOCKS с fail-closed проверкой |
| `tunnel/claude-oauth-bridge.ps1` | временно задаёт системный SOCKS proxy для Claude OAuth и восстанавливает прежние настройки |
| `tunnel/test-ai-bridge.ps1` | проверяет туннель, `/healthz`, SOCKS и kill-switch |
| `tunnel/setup-tunnel-task.cmd` | регистрирует скрытую задачу `AI-Bridge-Tunnel` |
| `hermes/config.yaml.example` | конфиг профиля Hermes (провайдер → мост) |
| `hermes/.env.example` | ключ-заглушка для Hermes |
| `hermes/launch.py` + `launch.cmd` | запуск Hermes с SOCKS-маршрутизацией через мост |
| `plugin/ai-quota/plugin.js` | desktop-плагин квот (забирает `/quota/*` с моста) |

## Настройка туннеля

Туннель поднимает на ПК два порта:

- `127.0.0.1:8801` — сам мост (`ssh -L 8801:127.0.0.1:8801`);
- `127.0.0.1:18081` — SOCKS-прокси через сервер (`ssh -D 18081`), через него
  Hermes ходит за веб-инструментами и фоновыми проверками;
- `127.0.0.1:18082` — loopback HTTP CONNECT → SOCKS адаптер (для клиентов,
  не принимающих SOCKS, например Claude Code), он же отдаёт PAC.

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

### Claude Code (изолированный контейнер)

Рекомендуемый способ — запускать Claude Code в отдельном Docker-контейнере с
жёстким egress-контролем. Любой TCP из контейнера (CLI, subprocess, плагин)
принудительно идёт в SSH SOCKS через `redsocks + iptables`, а UDP (QUIC, WebRTC,
прямой DNS) режется. Это сильнее, чем proxy-переменные: даже код, игнорирующий
`HTTP(S)_PROXY`, не выйдет в обход туннеля.

```powershell
.\tunnel\claude-container.ps1            # интерактивный запуск
.\tunnel\claude-container.ps1 -- --version
```

Требует запущенного Docker Desktop. Wrapper сам поднимает gateway (контейнер
`io-claude-gateway` с redsocks) и достраивает runner-образ при первом запуске.
OAuth-профиль живёт в Docker-томе `io-claude-state`, а не на хосте. Внутри Hermes
`claude` резолвится в этот runner через PATH-шим (`ai-bridge/claude.cmd`),
который добавляет `launch.py`.

Проверка egress (оба пути должны показать IP сервера):

```powershell
docker run --rm --network container:io-claude-gateway --mount type=bind,src=<repo>\client\claude-container\egress-test.js,dst=/e.js,ro --entrypoint node -e PROXY_IP=<host-gw> io-claude-runner:2.1.319 /e.js
```

`<host-gw>` — адрес `host.docker.internal` внутри Docker Desktop (обычно
`192.168.65.254`, смотри `docker run --rm --entrypoint getent alpine hosts host.docker.internal`).

### Claude Code (legacy wrapper, без Docker)

Альтернатива без контейнера — wrapper, который задаёт proxy-переменные и не
стартует при отсутствующем туннеле:

```powershell
.\tunnel\claude-bridge.ps1
.\tunnel\claude-bridge.ps1 -- --version
.\tunnel\claude-oauth-bridge.ps1
```

Wrapper не задаёт `ANTHROPIC_BASE_URL`: для OAuth-подписки Claude сохраняет
штатные Anthropic endpoints. Claude Code принимает HTTP(S)-proxy, но не SOCKS,
поэтому wrapper поднимает только на loopback HTTP CONNECT-адаптер `:18082`,
который передаёт соединения в SSH SOCKS `:18081`. Если туннель или этот адаптер
недоступны, Claude не запускается.

`claude-oauth-bridge.ps1` временно включает системный SOCKS для браузерного
OAuth, запускает Claude login и в `finally` восстанавливает прежние настройки
Windows proxy. Без реального входа его можно проверить так:

```powershell
.\tunnel\claude-oauth-bridge.ps1 -DryRun
```

### Системный прокси (PAC) и QUIC

Пока Hermes работает, `system-proxy-watchdog.ps1` (стартует из `launch.py`)
ставит системный прокси через PAC-файл, который отдаёт адаптер на
`http://127.0.0.1:18082/proxy.pac`:

- **публичные домены** → `PROXY 127.0.0.1:18082` (туннель);
- **внутренние/частные** (`isPlainHostName`, `*.evapps.ru`, `10.*`, `192.168.*`,
  `169.254.*`, `127.*`) → `DIRECT`.

PAC не резолвит DNS локально (никаких `isInNet` по hostname), поэтому публичные
имена резолвятся сервером через туннель и не светятся локальному резолверу.
Список внутренних доменов — в переменной `$internalDomains` внутри
`system-proxy-watchdog.ps1`; добавь туда свои корпоративные домены.

`tunnel-watchdog.ps1` дополнительно блокирует исходящий **UDP 443 (QUIC/HTTP3)**,
вынуждая браузер откатиться на TCP HTTP/2, который идёт через прокси, а не
напрямую. Правила `AI-Bridge-Block-Direct` (TCP 443 к провайдерам) и
`AI-Bridge-Block-QUIC` (UDP 443) включаются только пока Hermes/Claude запущен и
снимаются при выходе.

## Проверка

После установки и при диагностике выполни в PowerShell:

```powershell
.\tunnel\test-ai-bridge.ps1 -ExpectedEgressIp <ip-сервера>
```

Скрипт проверяет end-to-end путь до `/healthz` через SSH-туннель, SOCKS на
`127.0.0.1:18081`, внешний IP через SOCKS и включённое правило блокировки, если
процесс Hermes запущен. Он не отправляет запросы провайдерам и не читает ключи.
