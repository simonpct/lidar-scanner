#!/bin/bash
# Relance le test USB avec les bons droits.
#
# macOS capture automatiquement les appareils PTP via le service "PTPCamera".
# Il faut le tuer pour que gphoto2 / pyusb puissent accéder à la GoPro.
#
# Usage:
#   ./gopro_usb_test_sudo.sh

set -euo pipefail

echo "=== Arrêt du service PTPCamera de macOS ==="
echo "(c'est lui qui bloque l'accès USB à la GoPro)"
echo ""

# Tuer PTPCamera s'il tourne
if pgrep -x PTPCamera > /dev/null 2>&1; then
    echo "PTPCamera trouvé, arrêt..."
    sudo killall PTPCamera
    sleep 1
    echo "OK"
else
    echo "PTPCamera ne tourne pas."
fi

# Aussi tuer le Image Capture Agent
if pgrep -f "ImageCaptureAgent" > /dev/null 2>&1; then
    echo "ImageCaptureAgent trouvé, arrêt..."
    killall ImageCaptureAgent 2>/dev/null || true
    sleep 1
fi

echo ""
echo "=== Lancement du test USB avec sudo ==="
echo ""

# Lancer le test
sudo python3 "$(dirname "$0")/gopro_usb_test.py"
