#!/bin/bash
LOG="/var/log/centralized_security.log"
REPORT="/var/log/security_report.txt"
# =========================
# VALIDACIÓN
# =========================
if [[ ! -f "$LOG" ]]; then
echo "[ERROR] Log no encontrado: $LOG"
exit 1
fi
> "$REPORT"
DATE=$(date "+%Y-%m-%d %H:%M:%S")
# =========================
# PROCESAMIENTO (1 sola pasada)
# =========================
STATS=$(awk -F'[][]' '
/FAILED_LOGIN/ {
ip=$10
count[ip]++
total++
}
END {
for (i in count) {
if (count[i] > max) {
max=count[i]
top=i
}
}
print total, length(count), top, max
}' "$LOG")
FAILED=$(echo "$STATS" | awk '{print $1}')
UNIQUE_IPS=$(echo "$STATS" | awk '{print $2}')
TOP_IP=$(echo "$STATS" | awk '{print $3}')
TOP_COUNT=$(echo "$STATS" | awk '{print $4}')
# =========================
# EVENTOS FAIL2BAN
# =========================
BANS=$(grep -c "\[FAIL2BAN\] \[BAN\]" "$LOG")
# =========================
# SCORING DE RIESGO (corregido)
# =========================
RISK="LOW"
if (( TOP_COUNT >= 500 )); then
RISK="CRITICAL"
elif (( TOP_COUNT >= 100 && BANS > 0 )); then
RISK="HIGH"
elif (( TOP_COUNT >= 20 )); then
RISK="MEDIUM"
fi
# =========================
# GENERACIÓN DEL INFORME
# =========================
{
echo "===== INFORME DE SEGURIDAD ====="
echo "Fecha: $DATE"
echo ""
echo "Intentos fallidos: $FAILED"
echo "IPs únicas detectadas: $UNIQUE_IPS"
echo "IPs bloqueadas (Fail2Ban): $BANS"
echo "IP más activa: $TOP_IP ($TOP_COUNT intentos)"
echo "Nivel de riesgo: $RISK"
echo ""
echo "Resumen:"
case "$RISK" in
CRITICAL)
echo "- Ataque masivo automatizado detectado"
echo "- Alta probabilidad de fuerza bruta activa"
echo "- Recomendación: bloqueo a nivel firewall (iptables/nftables)"
;;
HIGH)
echo "- Actividad maliciosa confirmada"
echo "- Fail2Ban mitigando parcialmente"
echo "- Revisar configuración SSH (puerto, auth, rate limiting)"
;;
MEDIUM)
echo "- Actividad sospechosa detectada"
echo "- Posible enumeración o intentos de acceso"
;;
LOW)
echo "- Actividad baja o ruido normal del sistema"
;;
esac
# =========================
# CONTEXTO ADICIONAL
# =========================
echo ""
echo "Análisis adicional:"
if (( UNIQUE_IPS > 10 )); then
echo "- Posible ataque distribuido (múltiples IPs)"
fi
# Evitar división por cero
if (( FAILED > 0 && UNIQUE_IPS > 0 )); then
RATIO=$(( TOP_COUNT * 100 / FAILED ))
echo "- Concentración del ataque: $RATIO% en IP principal"
fi
if (( BANS == 0 && FAILED > 50 )); then
echo "- ALERTA: No hay bloqueos activos pese a múltiples intentos"
fi
} >> "$REPORT"
exit 0
