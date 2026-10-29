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
| `root/etc/netplan/`, `root/etc/nut/` | `/etc/netplan`, `/etc/nut` (root:600; contraseñas como `<REDACTED>`) |

## Nunca aquí

Secretos: `.env*`, `~/ibkr/env`, `~/ibkr/ibc/config.ini`, credenciales de cloudflared (`*.json`, `cert.pem`, tokens).
`sync.sh` escanea patrones de token y los valores de los `.env` vivos y aborta si encuentra alguno.
Datos, bases de datos y backups tampoco.

## Unidades del IB Gateway

`ibgateway*`, `ibkr-proxy`, `clientportal`, `xvfb` y `xfwm4` NO están aquí: su fuente es `ooda` `host/ibkr/` (con su
`sync.sh` y el cron `ibkr_units_drift`). Así cada unidad tiene un solo dueño.

## Ficheros de root

`/etc/netplan` y `/etc/nut` solo se leen con sudo. `sync.sh` los copia si `sudo -n` funciona; si no, conserva la copia
commiteada y `--check` no los compara. Para refrescarlos, en una sesión interactiva del M5:

```bash
sudo -v && ~/ooda-host-config/sync.sh && git -C ~/ooda-host-config diff --stat
```

Las contraseñas (netplan `password:`, `upsd.users`, campo de `MONITOR` en `upsmon.conf`) se sustituyen por `<REDACTED>`.
Al restaurar hay que volver a ponerlas a mano.

## Vigilancia

Cron diario `host_config_drift` (07:50) vía `with_run.sh`: `sync.sh --check`; rc 3 = divergencia → supervisor.

Restaurar en un host nuevo: copiar cada ruta del repo a su ruta viva, `systemctl --user daemon-reload`, `crontab crontab/nanoclaw.crontab`.
