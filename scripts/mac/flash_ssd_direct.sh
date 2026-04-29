#!/bin/bash
# =============================================================================
# flash_ssd_direct.sh — flash Ubuntu directement sur le SSD NVMe via USB-C
#
# Plus simple et plus rapide que prepare_sd_bootstrap.sh : pas de SD
# intermédiaire, pas de re-download sur le Pi.
#
# Pré-requis :
#   - Sortir le SSD NVMe du HAT Geekworm X1001
#   - Le brancher sur le Mac via un boîtier USB-C → M.2 NVMe
#   - L'EEPROM du Pi 5 doit être configurée pour booter NVMe
#     (par défaut sur firmware ≥ 2024-01)
#
# Usage : bash scripts/mac/flash_ssd_direct.sh
#
# Après :
#   1. Démonter le SSD
#   2. Le remettre dans le HAT du Pi
#   3. Brancher le Pi → boot direct sur SSD
#   4. ssh simon@lidar-scanner.local
#   5. sudo journalctl -u lidar-install -f
# =============================================================================

set -euo pipefail

# --- Config -----------------------------------------------------------------
HOSTNAME="lidar-scanner"
USERNAME="simon"
FULLNAME="Simon"
REPO_URL="https://github.com/simonpct/lidar-scanner.git"

WIFI1_SSID="Freebox-680CF2-IOT"
WIFI1_PSK="simoniot"
WIFI2_SSID="Simon"
WIFI2_PSK="simonpct"

UBUNTU_URL="https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
UBUNTU_IMG_XZ="$HOME/Downloads/ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz"

SSH_PUBKEY_FILE="$HOME/.ssh/id_ed25519.pub"

# --- Couleurs ---------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "\n${GREEN}▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "  ${RED}✗ $1${NC}"; exit 1; }

# --- Pré-requis -------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || fail "Script à lancer sur macOS"
[ -f "$SSH_PUBKEY_FILE" ] || fail "Clé SSH publique introuvable : $SSH_PUBKEY_FILE"
SSH_PUBKEY=$(cat "$SSH_PUBKEY_FILE")

if ! command -v xz &>/dev/null; then
    warn "xz non trouvé — installation via brew"
    brew install xz
fi

if ! command -v aria2c &>/dev/null; then
    warn "aria2c non trouvé — installation via brew"
    brew install aria2
fi

# --- Téléchargement de l'image ---------------------------------------------
step "Téléchargement Ubuntu 24.04 Server arm64"
NEED_DOWNLOAD=1
if [ -f "$UBUNTU_IMG_XZ" ]; then
    if xz -t "$UBUNTU_IMG_XZ" 2>/dev/null; then
        ok "Image .xz déjà présente et valide"
        NEED_DOWNLOAD=0
    else
        warn "Image .xz corrompue — re-téléchargement"
        rm -f "$UBUNTU_IMG_XZ"
    fi
fi

if [ "$NEED_DOWNLOAD" = "1" ]; then
    DL_DIR="$(dirname "$UBUNTU_IMG_XZ")"
    DL_NAME="$(basename "$UBUNTU_IMG_XZ")"
    aria2c -x 16 -s 16 -k 1M -c \
        --max-tries=5 --retry-wait=5 \
        --connect-timeout=15 --timeout=30 \
        --console-log-level=warn --summary-interval=5 \
        -d "$DL_DIR" -o "$DL_NAME" "$UBUNTU_URL"
    xz -t "$UBUNTU_IMG_XZ" || fail "Image téléchargée invalide"
    ok "Image téléchargée : $UBUNTU_IMG_XZ"
fi

# --- Sélection du SSD -------------------------------------------------------
step "Sélection du SSD NVMe (en USB-C)"

DISKS=()
while IFS= read -r line; do
    if [[ "$line" =~ ^/dev/(disk[0-9]+) ]]; then
        d="${BASH_REMATCH[1]}"
        [[ "$d" == "disk0" || "$d" == "disk1" ]] && continue
        if diskutil info "$d" 2>/dev/null | grep -q "Virtual: *Yes"; then
            continue
        fi
        DISKS+=("$d")
    fi
done < <(diskutil list physical | grep -E "^/dev/disk[0-9]+ ")

if [ ${#DISKS[@]} -eq 0 ]; then
    fail "Aucun disque détecté. Branchez le SSD via USB-C et relancez."
fi

echo ""
echo "  Disques détectés :"
echo ""
i=1
for d in "${DISKS[@]}"; do
    HUMAN_SIZE=$(diskutil info "/dev/$d" 2>/dev/null | grep "Disk Size" | head -1 | sed 's/Disk Size: *\([^(]*\).*/\1/' | xargs)
    NAME=$(diskutil info "/dev/$d" 2>/dev/null | grep "Device / Media Name" | sed 's/.*: *//' | xargs)
    PROTOCOL=$(diskutil info "/dev/$d" 2>/dev/null | grep "Protocol" | head -1 | sed 's/.*: *//' | xargs)
    printf "    ${GREEN}[%d]${NC} /dev/%s  —  %s  (%s, %s)\n" "$i" "$d" "$HUMAN_SIZE" "$NAME" "$PROTOCOL"
    i=$((i+1))
done
echo ""
echo -e "  ${YELLOW}⚠ Tout le contenu du disque sélectionné sera EFFACÉ.${NC}"
echo ""

read -p "  Numéro du SSD NVMe [1-${#DISKS[@]}] (ou Entrée pour annuler) : " CHOICE
[ -z "$CHOICE" ] && fail "Annulé"
[[ "$CHOICE" =~ ^[0-9]+$ ]] || fail "Choix invalide : '$CHOICE'"
[ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#DISKS[@]}" ] || fail "Numéro hors plage : $CHOICE"

SSD_DISK="${DISKS[$((CHOICE-1))]}"
SSD_DEV="/dev/$SSD_DISK"
SSD_RDEV="/dev/r$SSD_DISK"
[ -e "$SSD_DEV" ] || fail "$SSD_DEV n'existe pas"

# Garde-fou taille : refuser < 16 GB (clé USB), confirmer > 1 TB (probable disque externe)
SSD_BYTES=$(diskutil info "$SSD_DEV" 2>/dev/null | grep "Disk Size" | head -1 | sed 's/.*(\([0-9]*\) Bytes).*/\1/' | xargs)
SSD_GB=$((SSD_BYTES / 1000 / 1000 / 1000))

if [ "$SSD_GB" -lt 16 ]; then
    fail "Disque $SSD_DEV trop petit (${SSD_GB} GB < 16 GB) — probablement une clé USB, pas un SSD"
fi

if [ "$SSD_GB" -gt 1000 ]; then
    warn "Disque $SSD_DEV très gros (${SSD_GB} GB) — êtes-vous sûr que c'est le SSD NVMe ?"
fi

echo ""
diskutil info "$SSD_DEV" | grep -E "Device / Media Name|Disk Size|Protocol|Removable Media" || true
echo ""
read -p "Confirmer l'effacement de $SSD_DEV (${SSD_GB} GB) ? (oui/non) : " CONFIRM
[ "$CONFIRM" = "oui" ] || fail "Annulé"

# --- Flash de l'image -------------------------------------------------------
step "Démontage de $SSD_DEV"
diskutil unmountDisk "$SSD_DEV"

step "Flash de l'image sur le SSD (décompression à la volée)"
echo "  USB-C → ~3-5 min"
echo "  (Ctrl+T pour voir la progression)"
xz -dc "$UBUNTU_IMG_XZ" | sudo dd of="$SSD_RDEV" bs=4m
sync
ok "Flash terminé"

# --- Remontage --------------------------------------------------------------
step "Remontage de la partition system-boot"
diskutil unmountDisk "$SSD_DEV" 2>/dev/null || true
sleep 2
diskutil mountDisk "$SSD_DEV"
sleep 2

BOOT_MOUNT="/Volumes/system-boot"
[ -d "$BOOT_MOUNT" ] || fail "Partition system-boot non montée — réinsérez le SSD"

# --- network-config ---------------------------------------------------------
step "Configuration WiFi (network-config)"
cat > /tmp/network-config <<EOF
version: 2
wifis:
  wlan0:
    dhcp4: true
    optional: true
    access-points:
      "$WIFI1_SSID":
        password: "$WIFI1_PSK"
EOF

if [ -n "$WIFI2_SSID" ]; then
    cat >> /tmp/network-config <<EOF
      "$WIFI2_SSID":
        password: "$WIFI2_PSK"
EOF
fi

sudo cp /tmp/network-config "$BOOT_MOUNT/network-config"
ok "WiFi : $WIFI1_SSID${WIFI2_SSID:+, $WIFI2_SSID}"

# --- meta-data --------------------------------------------------------------
sudo tee "$BOOT_MOUNT/meta-data" > /dev/null <<EOF
instance-id: lidar-scanner-direct
local-hostname: $HOSTNAME
EOF

# --- user-data : user + service lidar-install ------------------------------
step "Configuration cloud-init (user-data)"
cat > /tmp/user-data <<EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true

users:
  - name: $USERNAME
    gecos: "$FULLNAME"
    groups: [adm, dialout, cdrom, sudo, audio, video, plugdev, games, users, input, render, netdev, gpio, i2c, spi]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: "$USERNAME"
    ssh_authorized_keys:
      - $SSH_PUBKEY

ssh_pwauth: true

package_update: true
package_upgrade: false
packages:
  - git
  - curl
  - wget

write_files:
  - path: /usr/local/bin/run_lidar_install.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Pas de -u : ROS2 setup.bash plante en strict mode
      set -eo pipefail
      LOG=/var/log/lidar-install.log
      exec > >(tee -a \$LOG) 2>&1
      echo "=== run_lidar_install.sh \$(date) ==="

      for i in {1..60}; do
          if ping -c1 -W2 github.com &>/dev/null; then break; fi
          echo "  attente réseau (\$i/60)..."
          sleep 5
      done

      cd /home/$USERNAME
      if [ ! -d lidar-scanner ]; then
          sudo -u $USERNAME git clone $REPO_URL lidar-scanner
      fi
      chown -R $USERNAME:$USERNAME /home/$USERNAME/lidar-scanner

      sudo -u $USERNAME bash /home/$USERNAME/lidar-scanner/rpi5/install.sh

  - path: /etc/systemd/system/lidar-install.service
    permissions: '0644'
    content: |
      [Unit]
      Description=LiDAR Scanner — installation auto au 1er boot
      After=network-online.target
      Wants=network-online.target
      ConditionPathExists=!/var/lib/lidar-install.done

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/run_lidar_install.sh
      ExecStartPost=/bin/touch /var/lib/lidar-install.done
      RemainAfterExit=true
      TimeoutStartSec=0
      StandardOutput=journal+console
      StandardError=journal+console

      [Install]
      WantedBy=multi-user.target

runcmd:
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, lidar-install.service ]
  - [ systemctl, start, --no-block, lidar-install.service ]
EOF

sudo cp /tmp/user-data "$BOOT_MOUNT/user-data"
ok "user-data écrit"

# --- SSH activé -------------------------------------------------------------
sudo touch "$BOOT_MOUNT/ssh"
ok "SSH activé"

# --- PCIe Gen 3 (Geekworm X1001) -------------------------------------------
step "Activation PCIe Gen 3 (Geekworm X1001)"
CONFIG_TXT="$BOOT_MOUNT/config.txt"
if [ -f "$CONFIG_TXT" ]; then
    if ! grep -q "^dtparam=pciex1" "$CONFIG_TXT"; then
        echo "" | sudo tee -a "$CONFIG_TXT" > /dev/null
        echo "# Geekworm X1001 NVMe HAT" | sudo tee -a "$CONFIG_TXT" > /dev/null
        echo "dtparam=pciex1" | sudo tee -a "$CONFIG_TXT" > /dev/null
        echo "dtparam=pciex1_gen=3" | sudo tee -a "$CONFIG_TXT" > /dev/null
        ok "PCIe Gen 3 activé"
    else
        ok "PCIe déjà configuré"
    fi
fi

# --- Démontage --------------------------------------------------------------
step "Démontage du SSD"
sync
diskutil unmountDisk "$SSD_DEV"
ok "SSD prêt à être retiré"

# --- Résumé -----------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  SSD prêt !${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "  Étapes suivantes :"
echo "   1. Débrancher le boîtier USB-C"
echo "   2. Sortir le SSD du boîtier"
echo "   3. Le remettre dans le HAT Geekworm X1001 du Pi"
echo "   4. Brancher l'alimentation du Pi"
echo "   5. Le Pi va :"
echo "        - booter directement depuis le SSD"
echo "        - se connecter au WiFi $WIFI1_SSID"
echo "        - cloner le repo + lancer rpi5/install.sh (~30-45 min)"
echo "   6. Suivre l'avancement :"
echo "        ssh $USERNAME@$HOSTNAME.local"
echo "        sudo journalctl -u lidar-install -f"
echo ""
echo "  Si le Pi ne boote pas → voir scripts/mac/README.md (section EEPROM)"
echo ""
