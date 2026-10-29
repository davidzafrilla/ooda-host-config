# ooda-host-config

Foto versionada de la configuración viva del host de producción (BOSGAME M5, usuario `nanoclaw`) que no está en los
repos de código. Se actualiza con `./sync.sh` y se commitea; `./sync.sh --check` (rc 3) avisa de divergencias.

## Mapa de repos del sistema OODA (29-oct-2026)

| Repo GitHub | Ramas | Contenido | Dónde se ejecuta |
|---|---|---|---|
| `davidzafrilla/ooda` | `unificada` (activa), `main` (espejo de `unificada`) | NanoClaw v2: agentes, host/ibkr, dashboard | M5 `~/nanoclaw-v2` |
| `davidzafrilla/ooda` | `master` | Proyecto /OODA del Mac (docs, reports, scripts). Linaje sin ancestro común con `main` | Mac |
| `davidzafrilla/ooda-tobe` | `main` | OODA-TO-BE: data lake, pipelines, unidades shadow | M5 `~/ooda-tobe` (origin = bare `~/git/ooda-tobe.git`) |
| `davidzafrilla/ooda-host-config` | `main` | Este repo: systemd --user, crontab, unidades de sistema propias, /usr/local/sbin, cloudflared | M5 `~/ooda-host-config` |

Remotos en el Mac: `origin` = GitHub; `host` = árbol o bare del M5; `mirror` (solo OODA-TO-BE) = `~/git/ooda-tobe-mirror.git`.

## Contenido

| Ruta del repo | Ruta viva |
|---|---|
| `systemd-user/` | `~/.config/systemd/user/` (unidades + drop-ins `*.d/*.conf`, sin `*.bak*`) |
| `crontab/nanoclaw.crontab` | `crontab -l` |
| `systemd-system/` | `/etc/systemd/system/` (lan-watchdog, ooda-*, drop-ins de nut-driver) |
| `sbin/` | `/usr/local/sbin/` (lan-watchdog, wifi-rescue) |
| `cloudflared/config.yml` | `~/.cloudflared/config.yml` |

## Nunca aquí

Secretos: `.env*`, `~/ibkr/env`, `~/ibkr/ibc/config.ini`, credenciales de cloudflared (`*.json`, `cert.pem`, tokens).
`sync.sh` escanea patrones de token y los valores de los `.env` vivos y aborta si encuentra alguno.
Datos, bases de datos y backups tampoco.

## Pendiente

`/etc/netplan/*` y `/etc/nut/*` son root:600: copiarlos exige sudo y redactar `upsd.users`/`upsmon.conf` (contraseñas NUT)
y cualquier `password:` de WiFi en netplan.

Restaurar en un host nuevo: copiar cada ruta del repo a su ruta viva, `systemctl --user daemon-reload`, `crontab crontab/nanoclaw.crontab`.
