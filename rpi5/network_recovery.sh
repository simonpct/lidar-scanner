#!/bin/bash
# =============================================================================
# network_recovery.sh — filet de sécurité au boot
#
# Si après le délai de boot aucune connexion WiFi n'est active (ni STA ni AP),
# active l'AP "LidarScanner" pour qu'on puisse récupérer le Pi via le hotspot
# (au lieu de devoir brancher écran HDMI + clavier).
#
# Lancé par lidar-network-recovery.service (oneshot après 60s de boot).
# =============================================================================

set -eo pipefail

WAIT_SECONDS=60
AP_CON="LidarScanner-AP"
LOG=/var/log/lidar-network-recovery.log

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== network_recovery.sh start ==="

# Attendre que NM soit prêt
for i in {1..20}; do
    if nmcli general status &>/dev/null; then break; fi
    sleep 2
done

# Boucle d'attente : laisser NM tenter ses connexions normales
log "Attente $WAIT_SECONDS s pour laisser NM se connecter naturellement..."
for ((i=0; i<WAIT_SECONDS; i+=5)); do
    if nmcli -t -f STATE,CONNECTIVITY general status 2>/dev/null | grep -qE "^connected"; then
        log "Réseau OK après $i s — pas besoin de fallback"
        exit 0
    fi
    sleep 5
done

# Toujours pas de réseau → activer l'AP de secours
log "Aucune connexion après $WAIT_SECONDS s — activation AP de secours"

# Garantir que les STA gardent autoconnect=yes (au cas où une session précédente l'aurait désactivé)
while IFS= read -r name; do
    [ -z "$name" ] && continue
    nmcli con modify "$name" connection.autoconnect yes 2>/dev/null || true
done < <(nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2=="802-11-wireless" {print $1}' | grep -vx "$AP_CON")

# Activer l'AP via network_mode.sh si dispo, sinon directement
if [ -x /usr/local/bin/network_mode.sh ]; then
    /usr/local/bin/network_mode.sh hotspot >> "$LOG" 2>&1 || log "network_mode.sh hotspot failed"
else
    nmcli con up "$AP_CON" 2>&1 | tee -a "$LOG" || log "nmcli con up $AP_CON failed"
fi

log "=== fin ==="
