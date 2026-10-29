#!/usr/bin/env bash
# Prueba de histéresis de lan-watchdog (29-oct-2026): stubs de ip/ping/logger/wifi-rescue en un directorio temporal.
set -euo pipefail
SRC="${1:-$(dirname "$0")/../sbin/lan-watchdog}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/run/systemd/network"
sed -e "s|/run/|$T/run/|g" -e "s|/usr/local/sbin/wifi-rescue|$T/bin/wifi-rescue|" "$SRC" > "$T/wd"
cat > "$T/bin/ip" <<'X'
#!/usr/bin/env bash
echo "default via 192.168.0.1 dev eno1"
X
cat > "$T/bin/ping" <<X
#!/usr/bin/env bash
[ "\$(cat $T/lan)" = up ]
X
printf '#!/usr/bin/env bash\n:\n' > "$T/bin/logger"
cat > "$T/bin/wifi-rescue" <<X
#!/usr/bin/env bash
echo "\$1" >> $T/calls
if [ "\$1" = on ]; then touch $T/run/systemd/network/90-wifi-rescue.network; else rm -f $T/run/systemd/network/90-wifi-rescue.network; fi
X
chmod +x "$T"/bin/*
step() { echo "$1" > "$T/lan"; PATH="$T/bin:$PATH" bash "$T/wd"; }
calls() { cat "$T/calls" 2>/dev/null | tr '\n' ' '; }
for i in 1 2 3; do step down; done
[ "$(calls)" = "on " ] || { echo "FALLA: 3 fallos deberían encender (calls=$(calls))"; exit 1; }
for i in $(seq 1 20); do step up; step down; done                 # cable que parpadea: ni off ni más on
[ "$(calls)" = "on " ] || { echo "FALLA: parpadeo no debe conmutar (calls=$(calls))"; exit 1; }
for i in $(seq 1 29); do step up; done
[ "$(calls)" = "on " ] || { echo "FALLA: 29 OK no deben apagar (calls=$(calls))"; exit 1; }
step up
[ "$(calls)" = "on off " ] || { echo "FALLA: 30 OK deben apagar una vez (calls=$(calls))"; exit 1; }
for i in 1 2 3 4 5; do step up; done
[ "$(calls)" = "on off " ] || { echo "FALLA: sin conmutaciones extra (calls=$(calls))"; exit 1; }
echo "PASA"
