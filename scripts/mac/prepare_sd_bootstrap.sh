#!/bin/bash
# =============================================================================
# prepare_sd_bootstrap.sh — à exécuter sur le Mac
#
# Flashe Ubuntu 24.04 Server arm64 sur une carte microSD et y dépose un
# cloud-init + un script de premier démarrage (firstboot_pi_to_nvme.sh).
#
# Au 1er boot du Pi avec cette SD :
#   1. Le Pi se connecte automatiquement au WiFi
#   2. Un service systemd one-shot lance firstboot_pi_to_nvme.sh
#   3. Ce script flashe Ubuntu sur le SSD NVMe (HAT Geekworm X1001)
#   4. Y dépose un cloud-init qui clonera le repo et lancera rpi5/install.sh
#   5. Configure l'EEPROM pour booter NVMe en priorité
#   6. Reboot → la SD peut être retirée
#
# Usage :
#   bash scripts/mac/prepare_sd_bootstrap.sh
# =============================================================================

set -euo pipefail

# --- Config (modifiable) ----------------------------------------------------
HOSTNAME="lidar-scanner"
USERNAME="simon"
FULLNAME="Simon"
GITHUB_USER="simonpct"
REPO_URL="https://github.com/simonpct/lidar-scanner.git"

# Deux WiFi par défaut
WIFI1_SSID="Freebox-680CF2-IOT"
WIFI1_PSK="simoniot"
WIFI2_SSID="Simon"   # demandé interactivement si vide
WIFI2_PSK="simonpct"

UBUNTU_URL="https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
UBUNTU_IMG_XZ="$HOME/Downloads/ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz"
UBUNTU_IMG="${UBUNTU_IMG_XZ%.xz}"

SSH_PUBKEY_FILE="$HOME/.ssh/id_ed25519.pub"

# --- Couleurs ---------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "\n${GREEN}▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "  ${RED}✗ $1${NC}"; exit 1; }

# --- Pré-requis -------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || fail "Ce script doit être lancé sur macOS"
[ -f "$SSH_PUBKEY_FILE" ] || fail "Clé SSH publique introuvable : $SSH_PUBKEY_FILE"
SSH_PUBKEY=$(cat "$SSH_PUBKEY_FILE")

if ! command -v xz &>/dev/null; then
    warn "xz non trouvé — installation via brew"
    brew install xz
fi

if ! command -v aria2c &>/dev/null; then
    warn "aria2c non trouvé — installation via brew (téléchargement multi-connexions)"
    brew install aria2
fi

# --- Second WiFi (interactif) -----------------------------------------------
if [ -z "$WIFI2_SSID" ]; then
    echo ""
    read -p "Second WiFi SSID (vide pour ignorer) : " WIFI2_SSID
    if [ -n "$WIFI2_SSID" ]; then
        read -s -p "Mot de passe pour $WIFI2_SSID : " WIFI2_PSK
        echo ""
    fi
fi

# --- Téléchargement de l'image Ubuntu ---------------------------------------
step "Téléchargement Ubuntu 24.04 Server arm64"

# Si l'image décompressée n'est pas là, on a besoin du .xz valide
if [ ! -f "$UBUNTU_IMG" ]; then
    # Vérifier l'intégrité du .xz s'il existe ; sinon (re)télécharger
    NEED_DOWNLOAD=1
    if [ -f "$UBUNTU_IMG_XZ" ]; then
        if xz -t "$UBUNTU_IMG_XZ" 2>/dev/null; then
            ok "Image .xz déjà présente et valide"
            NEED_DOWNLOAD=0
        else
            warn "Image .xz corrompue ou incomplète — re-téléchargement"
            rm -f "$UBUNTU_IMG_XZ"
        fi
    fi

    if [ "$NEED_DOWNLOAD" = "1" ]; then
        DL_DIR="$(dirname "$UBUNTU_IMG_XZ")"
        DL_NAME="$(basename "$UBUNTU_IMG_XZ")"

        download_image() {
            if command -v aria2c &>/dev/null; then
                # 16 connexions parallèles, contourne le throttle per-connection
                # -c : reprend un download interrompu
                # --max-tries=5 : retry au niveau aria2
                # --retry-wait=5 : 5s entre essais
                # --connect-timeout=15 : timeout connexion
                # --timeout=30 : timeout par socket si rien ne vient
                aria2c \
                    -x 16 -s 16 -k 1M \
                    -c \
                    --max-tries=5 \
                    --retry-wait=5 \
                    --connect-timeout=15 \
                    --timeout=30 \
                    --console-log-level=warn \
                    --summary-interval=5 \
                    -d "$DL_DIR" \
                    -o "$DL_NAME" \
                    "$UBUNTU_URL"
            else
                # Fallback curl avec timeouts agressifs
                curl -L --progress-bar -C - \
                     --speed-limit 50000 --speed-time 20 \
                     --retry 10 --retry-delay 3 --retry-connrefused \
                     --connect-timeout 15 \
                     -o "$UBUNTU_IMG_XZ" "$UBUNTU_URL"
            fi
        }

        download_image

        # Re-vérifier après download
        if ! xz -t "$UBUNTU_IMG_XZ" 2>/dev/null; then
            warn "Téléchargement corrompu — nouvelle tentative complète"
            rm -f "$UBUNTU_IMG_XZ" "$UBUNTU_IMG_XZ.aria2"
            download_image
            xz -t "$UBUNTU_IMG_XZ" || fail "Image .xz invalide après 2 tentatives"
        fi
        ok "Image téléchargée : $UBUNTU_IMG_XZ"
    fi

    step "Décompression de l'image (~3 GB)"
    xz -dk "$UBUNTU_IMG_XZ"
    ok "Décompressée : $UBUNTU_IMG"
else
    ok "Image .img déjà décompressée"
fi

# --- Sélection de la carte SD ----------------------------------------------
step "Sélection de la carte microSD"

# Lister tous les disques physiques sauf le disque système (disk0/disk1)
# Inclut aussi les SD readers internes (Mac avec slot SD)
DISKS=()
while IFS= read -r line; do
    if [[ "$line" =~ ^/dev/(disk[0-9]+) ]]; then
        d="${BASH_REMATCH[1]}"
        # Exclure le disque système
        [[ "$d" == "disk0" || "$d" == "disk1" ]] && continue
        # Exclure les "synthesized" (volumes APFS virtuels)
        if diskutil info "$d" 2>/dev/null | grep -q "Virtual: *Yes"; then
            continue
        fi
        DISKS+=("$d")
    fi
done < <(diskutil list physical | grep -E "^/dev/disk[0-9]+ ")

# Dédoublonner (au cas où)
UNIQUE_DISKS=()
for d in "${DISKS[@]}"; do
    skip=0
    for u in "${UNIQUE_DISKS[@]}"; do [ "$u" = "$d" ] && skip=1 && break; done
    [ $skip -eq 0 ] && UNIQUE_DISKS+=("$d")
done
DISKS=("${UNIQUE_DISKS[@]}")

if [ ${#DISKS[@]} -eq 0 ]; then
    fail "Aucune carte SD/USB détectée. Insérez la carte et relancez."
fi

echo ""
echo "  Disques externes détectés :"
echo ""
i=1
for d in "${DISKS[@]}"; do
    SIZE=$(diskutil info "/dev/$d" 2>/dev/null | grep "Disk Size" | head -1 | sed 's/.*(\([^)]*\) Bytes).*/\1/' | xargs)
    NAME=$(diskutil info "/dev/$d" 2>/dev/null | grep "Device / Media Name" | sed 's/.*: *//' | xargs)
    HUMAN_SIZE=$(diskutil info "/dev/$d" 2>/dev/null | grep "Disk Size" | head -1 | sed 's/Disk Size: *\([^(]*\).*/\1/' | xargs)
    PROTOCOL=$(diskutil info "/dev/$d" 2>/dev/null | grep "Protocol" | head -1 | sed 's/.*: *//' | xargs)
    printf "    ${GREEN}[%d]${NC} /dev/%s  —  %s  (%s, %s)\n" "$i" "$d" "$HUMAN_SIZE" "$NAME" "$PROTOCOL"
    i=$((i+1))
done
echo ""
echo -e "  ${YELLOW}⚠ Tout le contenu du disque sélectionné sera EFFACÉ.${NC}"
echo ""

read -p "  Numéro du disque cible [1-${#DISKS[@]}] (ou Entrée pour annuler) : " CHOICE
[ -z "$CHOICE" ] && fail "Annulé"
[[ "$CHOICE" =~ ^[0-9]+$ ]] || fail "Choix invalide : '$CHOICE'"
[ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#DISKS[@]}" ] || fail "Numéro hors plage : $CHOICE"

SD_DISK="${DISKS[$((CHOICE-1))]}"
SD_DEV="/dev/$SD_DISK"
SD_RDEV="/dev/r$SD_DISK"
[ -e "$SD_DEV" ] || fail "$SD_DEV n'existe pas"

# Garde-fou : refuser disk0/disk1 (probablement le disque interne)
if [[ "$SD_DISK" == "disk0" || "$SD_DISK" == "disk1" ]]; then
    fail "$SD_DISK est probablement votre disque interne — abandon"
fi

echo ""
diskutil info "$SD_DEV" | grep -E "Device / Media Name|Disk Size|Protocol|Removable Media" || true
echo ""
read -p "Confirmer l'effacement de $SD_DEV ? (oui/non) : " CONFIRM
[ "$CONFIRM" = "oui" ] || fail "Annulé"

# --- Flash de l'image -------------------------------------------------------
step "Démontage de $SD_DEV"
diskutil unmountDisk "$SD_DEV"

step "Flash de l'image (~5–15 min selon vitesse SD)"
echo "  (vous pouvez taper Ctrl+T pour voir la progression)"
sudo dd if="$UBUNTU_IMG" of="$SD_RDEV" bs=4m status=progress
sync
ok "Flash terminé"

# --- Remontage et configuration cloud-init ----------------------------------
step "Remontage de la partition system-boot"
# Sur macOS, après dd, il faut souvent éjecter/réinsérer ou re-monter
diskutil unmountDisk "$SD_DEV" 2>/dev/null || true
sleep 2
diskutil mountDisk "$SD_DEV"
sleep 2

BOOT_MOUNT="/Volumes/system-boot"
[ -d "$BOOT_MOUNT" ] || fail "Partition system-boot non montée — réinsérez la SD et relancez la config seule"

# --- network-config (Netplan via cloud-init) --------------------------------
step "Écriture de network-config"
NETCFG="$BOOT_MOUNT/network-config"

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

sudo cp /tmp/network-config "$NETCFG"
ok "network-config écrit (WiFi: $WIFI1_SSID${WIFI2_SSID:+, $WIFI2_SSID})"

# --- user-data (cloud-init) -------------------------------------------------
step "Écriture de user-data (cloud-init)"
USERDATA="$BOOT_MOUNT/user-data"

# On écrit le firstboot dans /boot/firmware/ pour qu'il survive et soit
# accessible à la fois depuis la SD et après reboot.
FIRSTBOOT_SRC="$(dirname "$0")/firstboot_pi_to_nvme.sh"
[ -f "$FIRSTBOOT_SRC" ] || fail "firstboot_pi_to_nvme.sh manquant à côté de ce script"

# Encoder en base64 pour cloud-init (write_files)
FIRSTBOOT_B64=$(base64 -i "$FIRSTBOOT_SRC")

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
  - xz-utils
  - parted
  - rsync

write_files:
  - path: /usr/local/bin/firstboot_pi_to_nvme.sh
    permissions: '0755'
    encoding: b64
    content: |
      $FIRSTBOOT_B64
  - path: /etc/systemd/system/firstboot-nvme.service
    permissions: '0644'
    content: |
      [Unit]
      Description=First boot - flash Ubuntu to NVMe and configure
      After=network-online.target cloud-final.service
      Wants=network-online.target
      ConditionPathExists=!/var/lib/firstboot-nvme.done

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/firstboot_pi_to_nvme.sh
      RemainAfterExit=true
      StandardOutput=journal+console
      StandardError=journal+console

      [Install]
      WantedBy=multi-user.target

# Variables passées au firstboot
  - path: /etc/firstboot-nvme.env
    permissions: '0644'
    content: |
      HOSTNAME=$HOSTNAME
      USERNAME=$USERNAME
      FULLNAME=$FULLNAME
      REPO_URL=$REPO_URL
      WIFI1_SSID=$WIFI1_SSID
      WIFI1_PSK=$WIFI1_PSK
      WIFI2_SSID=$WIFI2_SSID
      WIFI2_PSK=$WIFI2_PSK
      UBUNTU_URL=$UBUNTU_URL
  - path: /etc/firstboot-ssh-pubkey
    permissions: '0644'
    content: |
      $SSH_PUBKEY

runcmd:
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, firstboot-nvme.service ]
  - [ systemctl, start, firstboot-nvme.service ]
EOF

sudo cp /tmp/user-data "$USERDATA"
ok "user-data écrit"

# --- meta-data (vide mais requis par cloud-init NoCloud) --------------------
sudo tee "$BOOT_MOUNT/meta-data" > /dev/null <<EOF
instance-id: lidar-scanner-bootstrap
local-hostname: $HOSTNAME
EOF
ok "meta-data écrit"

# --- Activer SSH (fichier ssh marker) ---------------------------------------
sudo touch "$BOOT_MOUNT/ssh"
ok "SSH activé"

# --- Activer PCIe Gen 3 pour le HAT Geekworm X1001 --------------------------
step "Activation PCIe (Geekworm X1001)"
CONFIG_TXT="$BOOT_MOUNT/config.txt"
if [ -f "$CONFIG_TXT" ]; then
    if ! grep -q "^dtparam=pciex1" "$CONFIG_TXT"; then
        echo "" | sudo tee -a "$CONFIG_TXT" > /dev/null
        echo "# Geekworm X1001 NVMe HAT" | sudo tee -a "$CONFIG_TXT" > /dev/null
        echo "dtparam=pciex1" | sudo tee -a "$CONFIG_TXT" > /dev/null
        echo "dtparam=pciex1_gen=3" | sudo tee -a "$CONFIG_TXT" > /dev/null
        ok "PCIe Gen 3 activé dans config.txt"
    else
        ok "PCIe déjà configuré"
    fi
else
    warn "config.txt non trouvé sur la partition boot"
fi

# --- Démontage --------------------------------------------------------------
step "Démontage de la SD"
sync
diskutil unmountDisk "$SD_DEV"
ok "SD prête à être retirée"

# --- Résumé -----------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Carte SD prête !${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "  Étapes suivantes :"
echo "   1. Insérer la SD dans le Raspberry Pi 5 (avec le HAT X1001 + SSD)"
echo "   2. Brancher l'alimentation"
echo "   3. Le Pi va :"
echo "        - se connecter au WiFi $WIFI1_SSID"
echo "        - flasher Ubuntu sur le SSD NVMe"
echo "        - configurer l'EEPROM pour booter NVMe"
echo "        - rebooter"
echo "   4. Suivre l'avancement :"
echo "        ssh $USERNAME@$HOSTNAME.local"
echo "        sudo journalctl -u firstboot-nvme -f"
echo "   5. Quand le Pi reboote, retirer la SD."
echo "      Au boot suivant (sur SSD), rpi5/install.sh sera lancé."
echo ""
echo "  Le tout devrait prendre ~30–60 min selon la vitesse réseau."
echo ""
