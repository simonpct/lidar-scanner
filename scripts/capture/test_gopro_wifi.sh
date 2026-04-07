#!/bin/bash
# Test de prise de photo GoPro via WiFi depuis le RPi5.
#
# Ce script :
#   1. Se connecte au WiFi de la GoPro (coupe le WiFi maison)
#   2. Teste l'API GoPro (status + prise de photo)
#   3. Se reconnecte AUTOMATIQUEMENT au WiFi maison après 60s MAX
#
# SÉCURITÉ : un watchdog garantit le retour au WiFi maison,
# même si le script crash ou si la GoPro ne répond pas.
#
# Usage (sur le Pi):
#   nohup sudo bash test_gopro_wifi.sh &
#   # Attendre ~90s puis se reconnecter en SSH
#   cat /tmp/gopro_wifi_test.txt

set -uo pipefail

GOPRO_SSID="GoPro MAX"
GOPRO_PASS="wbD-rtF-hYf"
HOME_SSID="Freebox-680CF2"
TIMEOUT=60  # secondes max sur le WiFi GoPro

LOG="/tmp/gopro_wifi_test.txt"
VENV="/home/simon/lidar-scanner/.venv/bin/python3"

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
}

# ============================================================
# WATCHDOG : garantit le retour au WiFi maison
# ============================================================
restore_home_wifi() {
    log "=== RESTAURATION WiFi maison ==="
    # Supprimer le réseau GoPro de wpa_supplicant
    # et resélectionner le réseau maison
    GOPRO_NET=$(wpa_cli -i wlan0 list_networks 2>/dev/null | grep "GoPro" | awk '{print $1}')
    if [ -n "$GOPRO_NET" ]; then
        wpa_cli -i wlan0 remove_network "$GOPRO_NET" > /dev/null 2>&1
    fi

    # Resélectionner le réseau 0 (Freebox)
    wpa_cli -i wlan0 select_network 0 > /dev/null 2>&1
    wpa_cli -i wlan0 reassociate > /dev/null 2>&1
    sleep 5

    # Vérifier
    if ip addr show wlan0 | grep -q "inet "; then
        log "WiFi maison restauré!"
        ip addr show wlan0 | grep "inet " >> "$LOG"
    else
        log "ATTENTION: WiFi maison pas encore connecté. Tentative netplan..."
        netplan apply 2>/dev/null
        sleep 10
        if ip addr show wlan0 | grep -q "inet "; then
            log "WiFi maison restauré via netplan!"
        else
            log "ÉCHEC restauration WiFi. Redémarrage réseau..."
            systemctl restart systemd-networkd wpa_supplicant 2>/dev/null
            sleep 10
        fi
    fi
}

# Lancer le watchdog en arrière-plan
(
    sleep $TIMEOUT
    log "WATCHDOG: timeout ${TIMEOUT}s atteint, restauration forcée!"
    restore_home_wifi
) &
WATCHDOG_PID=$!

# S'assurer que le WiFi maison est restauré quoi qu'il arrive
trap "kill $WATCHDOG_PID 2>/dev/null; restore_home_wifi" EXIT

# ============================================================
# DÉBUT DU TEST
# ============================================================
echo "" > "$LOG"
log "============================================="
log "  TEST GOPRO WIFI — RPi5"
log "============================================="

# ---- Connexion au WiFi GoPro ----
log ""
log "[1/4] Connexion au WiFi GoPro ($GOPRO_SSID)..."

# Ajouter le réseau GoPro
NETID=$(wpa_cli -i wlan0 add_network 2>/dev/null | tail -1)
wpa_cli -i wlan0 set_network "$NETID" ssid "\"$GOPRO_SSID\"" > /dev/null 2>&1
wpa_cli -i wlan0 set_network "$NETID" psk "\"$GOPRO_PASS\"" > /dev/null 2>&1
wpa_cli -i wlan0 select_network "$NETID" > /dev/null 2>&1

# Attendre la connexion
for i in $(seq 1 15); do
    sleep 1
    if wpa_cli -i wlan0 status 2>/dev/null | grep -q "COMPLETED"; then
        break
    fi
done

# Attendre une IP du DHCP GoPro
sleep 3

if ip addr show wlan0 | grep -q "10.5.5"; then
    IP=$(ip addr show wlan0 | grep "inet " | awk '{print $2}')
    log "  Connecté! IP: $IP"
else
    log "  Pas d'IP 10.5.5.x — vérification..."
    ip addr show wlan0 | grep "inet " >> "$LOG"

    # Forcer DHCP
    dhclient wlan0 2>/dev/null
    sleep 3

    if ip addr show wlan0 | grep -q "10.5.5"; then
        log "  Connecté après dhclient!"
    else
        log "  ÉCHEC connexion GoPro WiFi"
        exit 1
    fi
fi

# ---- Test API GoPro ----
log ""
log "[2/4] Test API GoPro..."

STATUS=$(curl -s --max-time 5 "http://10.5.5.9/gp/gpControl/status" 2>&1)
if [ $? -eq 0 ] && [ -n "$STATUS" ]; then
    log "  API GoPro: OK"
    echo "$STATUS" > /tmp/gopro_status.json
else
    log "  API GoPro: ÉCHEC ($STATUS)"
    exit 1
fi

# ---- Prise de photo ----
log ""
log "[3/4] Prise de photo 360..."

$VENV -c "
import requests, time, json

print('  Mode photo...')
r = requests.get('http://10.5.5.9/gp/gpControl/command/mode?p=1', timeout=5)
print(f'  Mode: {r.status_code}')
time.sleep(1)

print('  SHUTTER!')
r = requests.get('http://10.5.5.9/gp/gpControl/command/shutter?p=1', timeout=5)
print(f'  Shutter: {r.status_code}')
time.sleep(4)  # stitching 360

print('  Récupération liste médias...')
r = requests.get('http://10.5.5.9/gp/gpMediaList', timeout=10)
media = r.json()

if media.get('media'):
    folder = media['media'][-1]['d']
    last = media['media'][-1]['fs'][-1]['n']
    size = media['media'][-1]['fs'][-1].get('s', '?')
    print(f'  Dernière photo: {folder}/{last} (taille: {size})')

    # Télécharger la photo
    print(f'  Téléchargement...')
    url = f'http://10.5.5.9:8080/videos/DCIM/{folder}/{last}'
    r = requests.get(url, stream=True, timeout=30)
    path = f'/tmp/gopro_test_{last}'
    with open(path, 'wb') as f:
        for chunk in r.iter_content(65536):
            f.write(chunk)
    import os
    size_mb = os.path.getsize(path) / (1024*1024)
    print(f'  Sauvegardé: {path} ({size_mb:.1f} MB)')
    print(f'  RÉSULTAT: SUCCÈS')
else:
    print('  Aucun média trouvé')
    print(f'  RÉSULTAT: ÉCHEC')
" 2>&1 | tee -a "$LOG"

# ---- Résumé ----
log ""
log "[4/4] Résumé"
log ""

if [ -f /tmp/gopro_test_*.JPG ] 2>/dev/null || [ -f /tmp/gopro_test_*.jpg ] 2>/dev/null; then
    log "  ✓ Connexion WiFi GoPro"
    log "  ✓ API GoPro"
    log "  ✓ Prise de photo 360"
    log "  ✓ Téléchargement photo"
    log ""
    log "  TOUT FONCTIONNE!"
else
    log "  ✓ Connexion WiFi GoPro"
    log "  ✓ API GoPro"
    log "  ? Vérifier les fichiers /tmp/gopro_test_*"
fi

log ""
log "  Restauration WiFi maison dans 5s..."
sleep 5

# Le trap EXIT va appeler restore_home_wifi automatiquement
