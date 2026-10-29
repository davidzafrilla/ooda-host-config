#!/bin/bash
# ooda-host-config ↔ configuración viva del BOSGAME M5 (29-oct-2026).
#
# Foto versionada de lo que el host ejecuta y no vive en los repos de código (ooda, ooda-tobe). Mapeo:
#   systemd-user/<unidad>[.d/*.conf]  ↔ ~/.config/systemd/user/
#   crontab/nanoclaw.crontab          ↔ crontab -l (usuario nanoclaw)
#   systemd-system/<unidad>           ↔ /etc/systemd/system/ (solo las unidades propias, legibles sin sudo)
#   sbin/<script>                     ↔ /usr/local/sbin/
#   cloudflared/config.yml            ↔ ~/.cloudflared/config.yml (SIN credenciales: ni *.json, ni cert.pem, ni tokens)
#   root/etc/{netplan,nut}/           ↔ /etc/netplan, /etc/nut (root:600): solo con `sudo -n` disponible (antes: sudo -v);
#                                       contraseñas sustituidas por <REDACTED>. Sin sudo se conserva la copia commiteada.
# Fuera a propósito: .env*, ~/ibkr/env, ibc/config.ini, *.bak*, y las unidades del IB Gateway (ibgateway*, ibkr-proxy,
# clientportal, xvfb, xfwm4): su fuente es ooda host/ibkr, con su propio sync.sh y el cron ibkr_units_drift.
#
#   sync.sh           copia lo vivo al repo (y quita lo que ya no existe), escanea secretos; después: git diff + commit
#   sync.sh --check   compara lo vivo con lo COMMITEADO (HEAD). rc 0 = igual; rc 3 = divergencia
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
UNITS="${UNITS_DIR:-$HOME/.config/systemd/user}"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
REPO_ONLY_RE='^(sync\.sh|README\.md|\.gitignore)$'
IBKR_UNITS_RE='^(ibgateway[^/]*\.(service|timer)|ibkr-proxy\.service|clientportal\.service|xvfb\.service|xfwm4\.service)(\.d/.*)?$'
ROOT_OK=0; sudo -n true 2>/dev/null && ROOT_OK=1

redact() {   # contraseñas de netplan (password:), upsd.users (password =) y upsmon.conf (5.º campo de MONITOR)
    sed -E -e 's/^([[:space:]]*password:[[:space:]]*).*/\1"<REDACTED>"/' \
           -e 's/^([[:space:]]*password[[:space:]]*=[[:space:]]*).*/\1<REDACTED>/I' \
           -e 's/^([[:space:]]*MONITOR[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+)[^[:space:]]+/\1<REDACTED>/'
}

collect() {   # lo vivo → $1
    local out="$1"
    mkdir -p "$out/systemd-user" "$out/crontab" "$out/systemd-system" "$out/sbin" "$out/cloudflared"
    (cd "$UNITS" && find . -maxdepth 2 \( -name '*.service' -o -name '*.timer' -o -name '*.path' -o -name '*.socket' -o -name '*.target' -o -path './*.d/*.conf' \) -type f ! -name '*.bak*' -printf '%P\n') |
        grep -Ev "$IBKR_UNITS_RE" | while IFS= read -r f; do mkdir -p "$out/systemd-user/$(dirname "$f")"; cp -p "$UNITS/$f" "$out/systemd-user/$f"; done
    crontab -l > "$out/crontab/nanoclaw.crontab"
    for f in /etc/systemd/system/lan-watchdog.* /etc/systemd/system/ooda-*.service /etc/systemd/system/ooda-*.timer; do
        [[ -f "$f" ]] && cp -p "$f" "$out/systemd-system/"
    done
    for d in /etc/systemd/system/nut-driver@*.service.d; do
        [[ -d "$d" ]] && { mkdir -p "$out/systemd-system/$(basename "$d")"; cp -p "$d"/*.conf "$out/systemd-system/$(basename "$d")/"; }
    done
    for f in /usr/local/sbin/*; do [[ -f "$f" && -r "$f" ]] && cp -p "$f" "$out/sbin/"; done
    cp -p "$HOME/.cloudflared/config.yml" "$out/cloudflared/config.yml"
    [[ "$ROOT_OK" -eq 1 ]] || return 0
    local f
    for f in $(sudo -n find /etc/netplan /etc/nut -type f ! -name '*.bak*' | sort); do
        mkdir -p "$out/root$(dirname "$f")"; sudo -n cat "$f" | redact > "$out/root$f"
    done
    if grep -rqiE 'password[[:space:]]*[=:][[:space:]]*"?[^"<[:space:]]' "$out/root"; then
        echo "contraseña sin redactar en root/ (revisa redact): $(grep -rliE 'password[[:space:]]*[=:][[:space:]]*"?[^"<[:space:]]' "$out/root" | sed "s#^$out/##" | tr '\n' ' ')" >&2; exit 1
    fi
}

scan() {   # rc 1 si hay algo con pinta de secreto en $1
    local hits
    hits="$(grep -rlE 'sk-ant-[A-Za-z0-9_-]{20}|[0-9]{8,10}:AA[A-Za-z0-9_-]{30}|BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{30}|AKIA[0-9A-Z]{16}|\bU[0-9]{7}\b|\bDU[0-9]{7}\b' "$1" || true)"
    local envs; envs="$(cat "$HOME"/nanoclaw-v2/.env "$HOME"/ooda-tobe/.env "$HOME"/ibkr/env 2>/dev/null | sed -nE 's/^[A-Za-z_][A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASS|HMAC|ACCOUNT)[A-Za-z0-9_]*=["'\'']?([^"'\'']{10,})["'\'']?$/\2/p')"
    [[ -n "$envs" ]] && hits+="$(grep -rlFf <(echo "$envs") "$1" || true)"
    [[ -z "$hits" ]] || { echo "SECRETO detectado, no se copia nada:" >&2; echo "$hits" | sed "s#^$1/##" | sort -u >&2; return 1; }
}

collect "$STAGE"
scan "$STAGE"

if [[ "${1:-}" == "--check" ]]; then
    skip='^$'; [[ "$ROOT_OK" -eq 1 ]] || { skip='^root/'; echo "(sin sudo -n: root/ no se compara)"; }
    (cd "$STAGE" && find . -type f -printf '%P\n' | sort) > "$STAGE.live"
    git -C "$HERE" ls-tree -r --name-only HEAD | grep -Ev "$REPO_ONLY_RE" | grep -Ev "$skip" | sort > "$STAGE.head"
    out="$(comm -23 "$STAGE.live" "$STAGE.head" | sed 's/^/NEW  /'
           comm -13 "$STAGE.live" "$STAGE.head" | sed 's/^/GONE /'
           comm -12 "$STAGE.live" "$STAGE.head" | while IFS= read -r f; do git -C "$HERE" show "HEAD:$f" | cmp -s - "$STAGE/$f" || echo "DIFF $f"; done)"
    rm -f "$STAGE.live" "$STAGE.head"
    sha="$(git -C "$HERE" rev-parse --short HEAD)"
    if [[ -n "$out" ]]; then echo "$out"; echo "Divergencia host vivo vs ooda-host-config (HEAD $sha): $HERE/sync.sh + commit"; exit 3; fi
    echo "OK: host vivo = ooda-host-config (HEAD $sha)"; exit 0
fi

dirs="systemd-user crontab systemd-system sbin cloudflared"
if [[ "$ROOT_OK" -eq 1 ]]; then dirs+=" root"; else echo "(sin sudo -n: root/ se conserva como está; para refrescarlo: sudo -v && $0)"; fi
for d in $dirs; do rm -rf "${HERE:?}/$d"; cp -rp "$STAGE/$d" "$HERE/$d"; done
echo "Copiados $(find "$STAGE" -type f | wc -l) ficheros a $HERE (revisa con: git -C $HERE status)"
