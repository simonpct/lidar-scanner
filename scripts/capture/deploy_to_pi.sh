#!/bin/bash
# Déployer les scripts de test sur le Raspberry Pi 5.
#
# Usage:
#   ./deploy_to_pi.sh pi@raspberrypi.local
#   ./deploy_to_pi.sh pi@192.168.1.10

set -euo pipefail

PI_HOST="${1:?Usage: $0 <user@pi-host>}"
PI_DIR="~/lidar-scanner"

echo "=== Déploiement sur $PI_HOST ==="

# Créer le dossier sur le Pi
ssh "$PI_HOST" "mkdir -p $PI_DIR/scripts/capture"

# Copier les scripts
echo "Copie des scripts..."
scp scripts/capture/gopro_ble_usb_test.py "$PI_HOST:$PI_DIR/scripts/capture/"
scp scripts/capture/gopro_control.py "$PI_HOST:$PI_DIR/scripts/capture/"
scp scripts/capture/scan_session.py "$PI_HOST:$PI_DIR/scripts/capture/"

# Installer les dépendances sur le Pi
echo ""
echo "Installation des dépendances..."
ssh "$PI_HOST" << 'REMOTE'
sudo apt-get update -qq
sudo apt-get install -y -qq gphoto2 bluetooth bluez python3-pip python3-dbus
pip3 install --break-system-packages bleak requests 2>/dev/null || pip3 install bleak requests

echo ""
echo "=== Vérification ==="
echo "gphoto2: $(gphoto2 --version 2>&1 | head -1)"
echo "bluetoothctl: $(bluetoothctl --version 2>&1)"
python3 -c "import bleak; print(f'bleak: {bleak.__version__}')" 2>/dev/null || echo "bleak: erreur import"
echo ""
echo "=== Prêt! ==="
echo "Sur le Pi, lance:"
echo "  cd ~/lidar-scanner"
echo "  python3 scripts/capture/gopro_ble_usb_test.py"
REMOTE

echo ""
echo "Déployé! Connecte-toi au Pi:"
echo "  ssh $PI_HOST"
echo "  cd $PI_DIR"
echo "  python3 scripts/capture/gopro_ble_usb_test.py"
