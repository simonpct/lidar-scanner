#!/bin/bash
# Test WiFi dual mode sur RPi5 :
#   - wlan0 : client connecté au WiFi de la GoPro Max
#   - ap0   : hotspot pour le téléphone (même puce, interface virtuelle)
#
# ATTENTION: ce script coupe le WiFi actuel (et donc le SSH).
# Il se reconnecte automatiquement au WiFi maison après le test.
# Les résultats sont sauvegardés dans ~/lidar-scanner/wifi_test_result.txt
#
# Usage:
#   sudo ./test_wifi_dual.sh <GOPRO_SSID> <GOPRO_PASS> <HOME_SSID> <HOME_PASS>
#
# Exemple:
#   sudo ./test_wifi_dual.sh "GoPro MAX" "wbD-rtF-hYf" "MaBoxSFR" "monpass123"
#
# Lancer en mode détaché (ne coupe pas si SSH tombe) :
#   nohup sudo ./test_wifi_dual.sh "GoPro MAX" "wbD-rtF-hYf" "MaBoxSFR" "monpass" &

set -euo pipefail

GOPRO_SSID="${1:?Usage: sudo $0 <GOPRO_SSID> <GOPRO_PASS> <HOME_SSID> <HOME_PASS>}"
GOPRO_PASS="${2:?Usage: sudo $0 <GOPRO_SSID> <GOPRO_PASS> <HOME_SSID> <HOME_PASS>}"
HOME_SSID="${3:?Donne le SSID de ton WiFi maison pour se reconnecter après}"
HOME_PASS="${4:?Donne le mot de passe de ton WiFi maison}"

HOTSPOT_SSID="LidarScanner"
HOTSPOT_PASS="scan3d2026"
HOTSPOT_IP="192.168.4.1"

# Log dans le home de l'utilisateur réel (pas root)
REAL_HOME=$(eval echo ~${SUDO_USER:-$USER})
LOG_FILE="$REAL_HOME/lidar-scanner/wifi_test_result.txt"
mkdir -p "$(dirname "$LOG_FILE")"

# Tout logger dans un fichier
exec > >(tee "$LOG_FILE") 2>&1

echo "============================================="
echo "  TEST WIFI DUAL MODE — RPi5"
echo "============================================="
echo ""
echo "  GoPro WiFi:  $GOPRO_SSID"
echo "  Hotspot:     $HOTSPOT_SSID / $HOTSPOT_PASS"
echo ""

# ---- ÉTAPE 1 : Vérifier les prérequis ----
echo "[1/5] Vérification des prérequis..."

MISSING=""
for cmd in nmcli iw hostapd dnsmasq; do
    if ! command -v $cmd &>/dev/null; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    echo "  Paquets manquants:$MISSING"
    echo "  Installation..."
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq network-manager iw hostapd dnsmasq 2>/dev/null

    # Re-vérifier
    for cmd in nmcli iw hostapd dnsmasq; do
        if ! command -v $cmd &>/dev/null; then
            echo "  ERREUR: $cmd toujours manquant. Installe-le manuellement."
            exit 1
        fi
    done
fi
echo "  OK: nmcli, iw, hostapd, dnsmasq"

# Vérifier que la puce WiFi supporte AP+STA
echo ""
echo "  Capacités WiFi:"
iw list 2>/dev/null | grep -A 8 "valid interface combinations" || echo "  (impossible de lire les capacités)"
echo ""

# Vérifier si AP+STA est supporté
if iw list 2>/dev/null | grep -A 8 "valid interface combinations" | grep -q "AP"; then
    echo "  → La puce WiFi supporte le mode AP"
else
    echo "  → Mode AP peut-être non supporté. On essaie quand même."
fi

# ---- ÉTAPE 2 : Créer l'interface virtuelle ap0 ----
echo ""
echo "[2/5] Création de l'interface virtuelle ap0..."

# Supprimer si elle existe déjà
iw dev ap0 del 2>/dev/null || true

# Créer ap0 en mode AP sur la même puce que wlan0
iw dev wlan0 interface add ap0 type __ap
ip link set ap0 up
ip addr add $HOTSPOT_IP/24 dev ap0 2>/dev/null || true

echo "  ap0 créée"
echo "  IP: $HOTSPOT_IP"

# ---- ÉTAPE 3 : Configurer et lancer le hotspot (ap0) ----
echo ""
echo "[3/5] Lancement du hotspot sur ap0..."

# Déterminer le canal de la GoPro (important : ap0 doit être sur le même canal)
# On va d'abord scanner pour trouver le canal
GOPRO_CHANNEL=$(nmcli -f SSID,CHAN dev wifi list 2>/dev/null | grep "$GOPRO_SSID" | awk '{print $NF}' | head -1)
if [ -z "$GOPRO_CHANNEL" ]; then
    echo "  GoPro pas visible dans le scan WiFi. Canal par défaut: 6"
    GOPRO_CHANNEL=6
else
    echo "  Canal GoPro détecté: $GOPRO_CHANNEL"
fi

# Config hostapd
cat > /tmp/hostapd_lidar.conf << EOF
interface=ap0
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=$GOPRO_CHANNEL
wmm_enabled=0
auth_algs=1
wpa=2
wpa_passphrase=$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Config dnsmasq (DHCP pour les clients du hotspot)
cat > /tmp/dnsmasq_lidar.conf << EOF
interface=ap0
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
bind-interfaces
EOF

# Arrêter les services existants si besoin
systemctl stop hostapd 2>/dev/null || true
killall hostapd 2>/dev/null || true
killall dnsmasq 2>/dev/null || true

# Lancer dnsmasq
dnsmasq -C /tmp/dnsmasq_lidar.conf --pid-file=/tmp/dnsmasq_lidar.pid &
sleep 1

# Lancer hostapd
hostapd /tmp/hostapd_lidar.conf -B -P /tmp/hostapd_lidar.pid
sleep 2

if pgrep hostapd > /dev/null; then
    echo "  Hotspot '$HOTSPOT_SSID' actif sur canal $GOPRO_CHANNEL"
else
    echo "  ÉCHEC du lancement de hostapd."
    echo "  Le mode AP+STA n'est peut-être pas supporté sur cette puce."
    cat /tmp/hostapd_lidar.conf
    # Cleanup
    iw dev ap0 del 2>/dev/null || true
    exit 1
fi

# ---- ÉTAPE 4 : Connecter wlan0 à la GoPro ----
echo ""
echo "[4/5] Connexion à la GoPro WiFi ($GOPRO_SSID) sur wlan0..."

# Déconnecter wlan0 de tout réseau actuel
nmcli device disconnect wlan0 2>/dev/null || true
sleep 1

# Connecter à la GoPro
nmcli device wifi connect "$GOPRO_SSID" password "$GOPRO_PASS" ifname wlan0

sleep 3

# Vérifier la connexion
echo ""
echo "  État des interfaces:"
echo "  ----- wlan0 (GoPro) -----"
ip addr show wlan0 | grep "inet " || echo "  Pas d'IP sur wlan0"
echo ""
echo "  ----- ap0 (Hotspot) -----"
ip addr show ap0 | grep "inet " || echo "  Pas d'IP sur ap0"

# ---- ÉTAPE 5 : Tester les deux ----
echo ""
echo "[5/5] Tests de connectivité..."

# Test GoPro (wlan0)
echo ""
echo "  Test GoPro (10.5.5.9)..."
if curl -s --max-time 5 "http://10.5.5.9/gp/gpControl/status" > /dev/null 2>&1; then
    echo "  ✓ GoPro accessible via wlan0!"

    # Récupérer le status
    STATUS=$(curl -s --max-time 5 "http://10.5.5.9/gp/gpControl/status")
    echo "  Status GoPro: $(echo $STATUS | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"Mode={d.get(\"status\",{}).get(\"43\",\"?\")}, Battery={d.get(\"status\",{}).get(\"2\",\"?\")}%")' 2>/dev/null || echo 'OK')"
else
    echo "  ✗ GoPro NON accessible"
fi

# Test Hotspot (ap0)
echo ""
echo "  Hotspot '$HOTSPOT_SSID' actif."
echo "  Connecte ton téléphone au WiFi '$HOTSPOT_SSID' (pass: $HOTSPOT_PASS)"
echo "  Le téléphone devrait obtenir une IP en 192.168.4.x"
echo ""

# Résumé
echo "============================================="
echo "  RÉSUMÉ"
echo "============================================="
echo ""

GOPRO_OK=false
if curl -s --max-time 3 "http://10.5.5.9/gp/gpControl/status" > /dev/null 2>&1; then
    GOPRO_OK=true
fi

HOTSPOT_OK=false
if pgrep hostapd > /dev/null; then
    HOTSPOT_OK=true
fi

echo "  GoPro WiFi (wlan0):    $( [ "$GOPRO_OK" = true ] && echo '✓' || echo '✗' )"
echo "  Hotspot (ap0):         $( [ "$HOTSPOT_OK" = true ] && echo '✓' || echo '✗' )"
echo ""

if [ "$GOPRO_OK" = true ] && [ "$HOTSPOT_OK" = true ]; then
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║  DUAL WIFI FONCTIONNE!                        ║"
    echo "  ║                                               ║"
    echo "  ║  wlan0 → GoPro (contrôle + download)          ║"
    echo "  ║  ap0   → Hotspot téléphone (monitoring)       ║"
    echo "  ║  eth0  → Unitree L2 LiDAR                     ║"
    echo "  ║                                               ║"
    echo "  ║  Pas de dongle nécessaire!                     ║"
    echo "  ╚═══════════════════════════════════════════════╝"
else
    echo "  Le dual mode ne fonctionne pas complètement."
    echo "  Un dongle WiFi USB (~5€) sera nécessaire."
fi

echo ""
echo "============================================="
echo "  CLEANUP — Retour au WiFi maison"
echo "============================================="
echo ""

# Arrêter le hotspot
killall hostapd 2>/dev/null || true
killall dnsmasq 2>/dev/null || true
iw dev ap0 del 2>/dev/null || true
echo "  Hotspot arrêté"

# Reconnecter au WiFi maison
echo "  Reconnexion à '$HOME_SSID'..."
nmcli device disconnect wlan0 2>/dev/null || true
sleep 2
nmcli device wifi connect "$HOME_SSID" password "$HOME_PASS" ifname wlan0 2>&1 || true
sleep 3

# Vérifier
if ip addr show wlan0 | grep -q "inet "; then
    echo "  ✓ Reconnecté au WiFi maison!"
    ip addr show wlan0 | grep "inet "
else
    echo "  ✗ Pas de reconnexion. Le Pi est accessible via Ethernet si disponible."
fi

echo ""
echo "  Résultats sauvegardés dans: $LOG_FILE"
echo "  Terminé à $(date)"
