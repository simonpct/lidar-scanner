#!/bin/bash
# =============================================================================
# firstboot_pi_to_nvme.sh — exécuté sur le Pi au 1er boot depuis la SD
#
# 1. Détecte le SSD NVMe (HAT Geekworm X1001)
# 2. Télécharge Ubuntu 24.04 Server arm64
# 3. Flashe l'image sur le NVMe
# 4. Y dépose un cloud-init qui :
#       - recrée l'utilisateur, WiFi, SSH
#       - clone le repo et lance rpi5/install.sh
# 5. Configure l'EEPROM (BOOT_ORDER=0xf416 → NVMe d'abord)
# 6. Reboot
# =============================================================================

set -euo pipefail

# Charger les variables (HOSTNAME, USERNAME, REPO_URL, WIFI*, UBUNTU_URL)
source /etc/firstboot-nvme.env
SSH_PUBKEY=$(cat /etc/firstboot-ssh-pubkey)

LOG="/var/log/firstboot-nvme.log"
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "========================================================================"
echo "  firstboot_pi_to_nvme.sh — $(date)"
echo "========================================================================"

# --- Détecter le NVMe ------------------------------------------------------
echo "▶ Détection du SSD NVMe..."
NVME=""
for dev in /dev/nvme0n1 /dev/nvme1n1; do
    [ -b "$dev" ] && NVME="$dev" && break
done

if [ -z "$NVME" ]; then
    echo "  ✗ Aucun NVMe détecté !"
    echo "  Vérifiez :"
    echo "   - le HAT X1001 est bien branché"
    echo "   - dtparam=pciex1 est dans /boot/firmware/config.txt"
    echo "   - lsblk :"
    lsblk
    exit 1
fi
echo "  ✓ NVMe : $NVME ($(lsblk -dno SIZE $NVME))"

# --- Récupérer l'image (locale ou téléchargement) --------------------------
# Le Mac a déposé l'image sur /boot/firmware/ubuntu-image.img.xz si possible.
# Sinon, fallback sur le téléchargement réseau.
LOCAL_XZ="/boot/firmware/ubuntu-image.img.xz"
IMG_XZ="/tmp/ubuntu.img.xz"

if [ -f "$LOCAL_XZ" ] && xz -t "$LOCAL_XZ" 2>/dev/null; then
    echo "▶ Image locale trouvée sur la SD : $LOCAL_XZ"
    XZ_SRC="$LOCAL_XZ"
    echo "  ✓ Pas de téléchargement nécessaire (gain ~10-15 min)"
else
    if [ -f "$LOCAL_XZ" ]; then
        echo "  ⚠ Image locale corrompue — fallback téléchargement"
    else
        echo "▶ Pas d'image locale — téléchargement depuis $UBUNTU_URL"
    fi
    if command -v aria2c &>/dev/null; then
        aria2c -x 16 -s 16 -k 1M -c \
               --max-tries=5 --retry-wait=5 \
               --connect-timeout=15 --timeout=30 \
               --console-log-level=warn --summary-interval=5 \
               -d /tmp -o "$(basename $IMG_XZ)" "$UBUNTU_URL"
    else
        curl -L --progress-bar -C - \
             --speed-limit 50000 --speed-time 20 \
             --retry 10 --retry-delay 3 --retry-connrefused \
             --connect-timeout 15 \
             -o "$IMG_XZ" "$UBUNTU_URL"
    fi
    xz -t "$IMG_XZ" || { echo "  ✗ Image téléchargée invalide"; exit 1; }
    XZ_SRC="$IMG_XZ"
fi
echo "  ✓ Image prête : $XZ_SRC ($(du -h $XZ_SRC | cut -f1))"

# --- Flash sur NVMe (décompression à la volée) -----------------------------
echo "▶ Flash de l'image sur $NVME (décompression à la volée, ~5–10 min)..."
# Démonter au cas où
for part in $(lsblk -lno NAME "$NVME" | tail -n +2); do
    umount "/dev/$part" 2>/dev/null || true
done

# xz -dc | dd : pas besoin de décompresser sur disque (~3 GB économisés)
xz -dc "$XZ_SRC" | dd of="$NVME" bs=4M status=progress conv=fsync iflag=fullblock
sync
echo "  ✓ Flash terminé"

# Cleanup : libérer la place sur SD si on a utilisé l'image locale
# (seulement après flash réussi, pour pouvoir réessayer en cas d'échec)
if [ "$XZ_SRC" = "$LOCAL_XZ" ]; then
    rm -f "$LOCAL_XZ"
    echo "  ✓ Image locale supprimée (place libérée sur SD)"
fi

# Forcer le kernel à relire la table de partitions
partprobe "$NVME" || true
sleep 3

# --- Identifier les partitions du NVMe -------------------------------------
# Sur Ubuntu Pi : p1=system-boot (FAT), p2=writable (ext4)
NVME_BOOT="${NVME}p1"
NVME_ROOT="${NVME}p2"

[ -b "$NVME_BOOT" ] || { echo "  ✗ $NVME_BOOT introuvable"; lsblk "$NVME"; exit 1; }
[ -b "$NVME_ROOT" ] || { echo "  ✗ $NVME_ROOT introuvable"; lsblk "$NVME"; exit 1; }

# --- Monter system-boot et écrire cloud-init -------------------------------
echo "▶ Configuration cloud-init sur le NVMe..."
MNT="/mnt/nvme-boot"
mkdir -p "$MNT"
mount "$NVME_BOOT" "$MNT"

# network-config (mêmes WiFi)
cat > "$MNT/network-config" <<EOF
version: 2
wifis:
  wlan0:
    dhcp4: true
    optional: true
    access-points:
      "$WIFI1_SSID":
        password: "$WIFI1_PSK"
EOF

if [ -n "${WIFI2_SSID:-}" ]; then
    cat >> "$MNT/network-config" <<EOF
      "$WIFI2_SSID":
        password: "$WIFI2_PSK"
EOF
fi

# meta-data
cat > "$MNT/meta-data" <<EOF
instance-id: lidar-scanner-nvme
local-hostname: $HOSTNAME
EOF

# user-data : crée user, lance install.sh
cat > "$MNT/user-data" <<EOF
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

      # Attendre internet
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

      # Lancer l'install en tant qu'utilisateur (le script fait du sudo lui-même)
      sudo -u $USERNAME bash /home/$USERNAME/lidar-scanner/rpi5/install.sh

  - path: /etc/systemd/system/lidar-install.service
    permissions: '0644'
    content: |
      [Unit]
      Description=LiDAR Scanner — installation auto au 1er boot SSD
      After=network-online.target cloud-final.service
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

# Activer SSH
touch "$MNT/ssh"

# Activer PCIe Gen 3 dans config.txt du NVMe (le Pi doit voir le HAT pour booter)
if [ -f "$MNT/config.txt" ]; then
    if ! grep -q "^dtparam=pciex1" "$MNT/config.txt"; then
        cat >> "$MNT/config.txt" <<'EOF'

# Geekworm X1001 NVMe HAT
dtparam=pciex1
dtparam=pciex1_gen=3
EOF
    fi
fi

sync
umount "$MNT"
echo "  ✓ cloud-init configuré sur le NVMe"

# --- Configurer l'EEPROM pour booter NVMe en priorité ----------------------
echo "▶ Configuration EEPROM (BOOT_ORDER=0xf416 → NVMe d'abord)..."
if command -v rpi-eeprom-config &>/dev/null; then
    EEPROM_CONF=$(mktemp)
    rpi-eeprom-config > "$EEPROM_CONF"
    if grep -q "^BOOT_ORDER=" "$EEPROM_CONF"; then
        sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=0xf416/' "$EEPROM_CONF"
    else
        echo "BOOT_ORDER=0xf416" >> "$EEPROM_CONF"
    fi
    # PCIE_PROBE=1 pour activer la détection NVMe au boot
    if grep -q "^PCIE_PROBE=" "$EEPROM_CONF"; then
        sed -i 's/^PCIE_PROBE=.*/PCIE_PROBE=1/' "$EEPROM_CONF"
    else
        echo "PCIE_PROBE=1" >> "$EEPROM_CONF"
    fi
    rpi-eeprom-config --apply "$EEPROM_CONF" || echo "  ⚠ rpi-eeprom-config a échoué (pas critique)"
    rm -f "$EEPROM_CONF"
    echo "  ✓ EEPROM configurée (NVMe avant SD)"
else
    echo "  ⚠ rpi-eeprom-config non disponible — installer rpi-eeprom"
    apt-get install -y rpi-eeprom 2>/dev/null || true
fi

# --- Marqueur + reboot ------------------------------------------------------
touch /var/lib/firstboot-nvme.done

echo ""
echo "========================================================================"
echo "  ✓ NVMe prêt !"
echo "  Le Pi va rebooter dans 10 s."
echo "  → Retirez la SD pendant ce temps."
echo "  → Au boot suivant, rpi5/install.sh sera lancé automatiquement."
echo "========================================================================"
echo ""

sleep 10
systemctl reboot
