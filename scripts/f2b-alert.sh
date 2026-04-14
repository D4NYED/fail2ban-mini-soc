#!/bin/bash

# =========================
# Configuración
# =========================
LOGFILE="/var/log/fail2ban_custom.log"
STATEFILE="/var/log/fail2ban_state.log"
LOCKFILE="/var/log/fail2ban_state.lock"
WINDOW=600
DEBUG="${DEBUG:-false}"

# =========================
# Función debug
# =========================
debug_log() {
    if [[ "$DEBUG" == "true" ]]; then
        logger -t f2b-debug "$1"
    fi
}

# =========================
# Parámetros de entrada
# =========================
IP="$1"
JAIL="$2"

# =========================
# Validaciones básicas
# =========================
if [[ -z "$IP" || -z "$JAIL" ]]; then
    debug_log "ERROR: Parámetros inválidos"
    exit 1
fi

if ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    debug_log "ERROR: IP inválida $IP"
    exit 1
fi

debug_log "Inicio script - IP: $IP - JAIL: $JAIL"

# =========================
# Variables de tiempo
# =========================
NOW=$(date +%s)
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
HOSTNAME=$(hostname)

# =========================
# Crear archivos si no existen
# =========================
touch "$STATEFILE" "$LOGFILE" "$LOCKFILE"

# =========================
# Sección crítica con lock
# =========================
(
flock -x 200

LINE=$(grep "^$IP|" "$STATEFILE")

# =========================
# Limpieza global de timestamps antiguos
# =========================
TMP_STATE="${STATEFILE}.clean"

awk -F'|' -v now="$NOW" -v window="$WINDOW" '
{
    ip=$1
    split($2, times, ",")
    new_times=""
    for (i in times) {
        if (now - times[i] <= window) {
            new_times = new_times times[i] ","
        }
    }
    if (new_times != "") {
        sub(/,$/, "", new_times)
        print ip "|" new_times
    }
}
' "$STATEFILE" > "$TMP_STATE"

mv "$TMP_STATE" "$STATEFILE"

debug_log "Limpieza de STATEFILE ejecutada"

if [[ -n "$LINE" ]]; then
    OLD_TIMES=$(echo "$LINE" | cut -d'|' -f2)
    COUNT=0
    NEW_TIMES=""

    IFS=',' read -ra TIMES <<< "$OLD_TIMES"
    for T in "${TIMES[@]}"; do
        if (( NOW - T <= WINDOW )); then
            NEW_TIMES+="$T,"
            ((COUNT++))
        fi
    done

    NEW_TIMES+="$NOW"
    ((COUNT++))
    NEW_TIMES="${NEW_TIMES%,}"
else
    NEW_TIMES="$NOW"
    COUNT=1
fi

debug_log "Intentos en ventana para $IP: $COUNT"

# =========================
# Actualizar estado
# =========================
grep -v "^$IP|" "$STATEFILE" > "${STATEFILE}.tmp"
echo "$IP|$NEW_TIMES" >> "${STATEFILE}.tmp"
mv "${STATEFILE}.tmp" "$STATEFILE"

# =========================
# Clasificación de severidad
# =========================
if (( COUNT >= 10 )); then
    SEVERITY="CRITICAL"
elif (( COUNT >= 5 )); then
    SEVERITY="HIGH"
else
    SEVERITY="MEDIUM"
fi

debug_log "Severidad asignada: $SEVERITY"

# =========================
# Generación de log JSON
# =========================
JSON_LOG="{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"ip\":\"$IP\",\"servicio\":\"$JAIL\",\"intentos_10m\":$COUNT,\"severity\":\"$SEVERITY\",\"evento\":\"intrusion_blocked\"}"

echo "$JSON_LOG" >> "$LOGFILE"

debug_log "Log JSON generado para $IP"

) 200>>"$LOCKFILE"

# =========================
# Envío a syslog
# =========================
logger -t fail2ban-custom "[ALERTA][$SEVERITY] $IP ($COUNT intentos en 10m) en $JAIL"

debug_log "Evento enviado a syslog"

exit 0
