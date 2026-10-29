#!/bin/bash
# ooda-host-config ↔ configuración viva del BOSGAME M5 (29-oct-2026).
#
# Foto versionada de lo que el host ejecuta y no vive en los repos de código (ooda, ooda-tobe). Mapeo:
#   systemd-user/<unidad>[.d/*.conf]  ↔ ~/.config/systemd/user/
#   crontab/nanoclaw.crontab          ↔ crontab -l (usuario nanoclaw)
#   systemd-system/<unidad>           ↔ /etc/systemd/system/ (solo las unidades propias, legibles sin sudo)
#   sbin/<script>                     ↔ /usr/local/sbin/
#   cloudflared/config.yml            ↔ ~/.cloudflared/config.yml (SIN credenciales: ni *.json, ni cert.pem, ni tokens)
# Fuera a propósito: .env*, ~/ibkr/env, ibc/config.ini, *.bak*, y /etc/netplan y /etc/nut (root:600; ver README).
# Las fuentes de las unidades del IB Gateway siguen en ooda: host/ibkr (su sync.sh); aquí se fotografían igual.
#
#   sync.sh           copia lo vivo al repo (y quita lo que ya no existe), escanea secretos; después: git diff + commit
#   sync.sh --check   compara lo vivo con lo COMMITEADO (HEAD). rc 0 = igual; rc 3 = divergencia
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
UNITS="${UNITS_DIR:-$HOME/.config/systemd/user}"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
REPO_ONLY_RE='^(sync\.sh|README\.md|\.gitignore)$'

collect() {   # lo vivo → $1
    local out="$1"
    mkdir -p "$out/systemd-user" "$out/crontab" "$out/systemd-system" "$out/sbin" "$out/cloudflared"
    (cd "$UNITS" && find . -maxdepth 2 \( -name '*.service' -o -name '*.timer' -o -name '*.path' -o -name '*.socket' -o -name '*.target' -o -path './*.d/*.conf' \) -type f ! -name '*.bak*' -printf '%P\n') |
        while IFS= read -r f; do mkdir -p "$out/systemd-user/$(dirname "$f")"; cp -p "$UNITS/$f" "$out/systemd-user/$f"; done
    crontab -l > "$out/crontab/nanoclaw.crontab"
    for f in /etc/systemd/system/lan-watchdog.* /etc/systemd/system/ooda-*.service /etc/systemd/system/ooda-*.timer; do
        [[ -f "$f" ]] && cp -p "$f" "$out/systemd-system/"
    done
    for d in /etc/systemd/system/nut-driver@*.service.d; do
        [[ -d "$d" ]] && { mkdir -p "$out/systemd-system/$(basename "$d")"; cp -p "$d"/*.conf "$out/systemd-system/$(basename "$d")/"; }
    done
    for f in /usr/local/sbin/*; do [[ -f "$f" && -r "$f" ]] && cp -p "$f" "$out/sbin/"; done
    cp -p "$HOME/.cloudflared/config.yml" "$out/cloudflared/config.yml"
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
    (cd "$STAGE" && find . -type f -printf '%P\n' | sort) > "$STAGE.live"
    git -C "$HERE" ls-tree -r --name-only HEAD | grep -Ev "$REPO_ONLY_RE" | sort > "$STAGE.head"
    out="$(comm -23 "$STAGE.live" "$STAGE.head" | sed 's/^/NEW  /'
           comm -13 "$STAGE.live" "$STAGE.head" | sed 's/^/GONE /'
           comm -12 "$STAGE.live" "$STAGE.head" | while IFS= read -r f; do git -C "$HERE" show "HEAD:$f" | cmp -s - "$STAGE/$f" || echo "DIFF $f"; done)"
    rm -f "$STAGE.live" "$STAGE.head"
    sha="$(git -C "$HERE" rev-parse --short HEAD)"
    if [[ -n "$out" ]]; then echo "$out"; echo "Divergencia host vivo vs ooda-host-config (HEAD $sha): $HERE/sync.sh + commit"; exit 3; fi
    echo "OK: host vivo = ooda-host-config (HEAD $sha)"; exit 0
fi

for d in systemd-user crontab systemd-system sbin cloudflared; do rm -rf "${HERE:?}/$d"; cp -rp "$STAGE/$d" "$HERE/$d"; done
echo "Copiados $(find "$STAGE" -type f | wc -l) ficheros a $HERE (revisa con: git -C $HERE status)"
