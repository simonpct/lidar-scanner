#!/bin/bash
# =============================================================================
# LiDAR Scanner — Installation complète Raspberry Pi 5
# Ubuntu 24.04 Server (ARM64) sur SSD NVMe
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/simonpct/lidar-scanner/main/rpi5/install.sh | bash
#   # ou
#   git clone https://github.com/simonpct/lidar-scanner.git ~/lidar-scanner
#   bash ~/lidar-scanner/rpi5/install.sh
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/simonpct/lidar-scanner.git"
SDK_URL="https://github.com/unitreerobotics/unilidar_sdk2.git"
INSTALL_DIR="$HOME/lidar-scanner"
SDK_DIR="$HOME/unilidar_sdk2"
FASTLIO_DIR="$HOME/FAST_LIO"
FASTLIO_URL="https://github.com/MIT-SPARK/spark-fast-lio.git"
VENV_DIR="$INSTALL_DIR/rpi5/.venv"
SCAN_DIR="$HOME/scans"
USER=$(whoami)
ERRORS=()

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step()  { echo -e "\n${GREEN}[$(date +%H:%M:%S)] ▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "  ${RED}✗ $1${NC}"; ERRORS+=("$1"); }

# =============================================================================
# 1. Pré-requis système
# =============================================================================
step "Mise à jour du système"
sudo apt update && sudo apt upgrade -y

step "Installation des paquets système"
sudo apt install -y \
    build-essential cmake git curl wget \
    python3 python3-venv python3-pip \
    net-tools wireless-tools \
    software-properties-common

# Check
for cmd in g++ cmake git python3 curl; do
    if command -v $cmd &>/dev/null; then
        ok "$cmd $(command -v $cmd)"
    else
        fail "$cmd non trouvé"
    fi
done

# =============================================================================
# 2. ROS2 Jazzy
# =============================================================================
step "Installation de ROS2 Jazzy"
if [ ! -d /opt/ros/jazzy ]; then
    sudo apt install -y software-properties-common
    sudo add-apt-repository universe -y
    sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
    sudo apt update
    sudo apt install -y ros-jazzy-desktop ros-jazzy-pcl-ros
else
    warn "ROS2 Jazzy déjà installé"
fi

# Check
source /opt/ros/jazzy/setup.bash
if command -v ros2 &>/dev/null; then
    ok "ros2 CLI disponible ($(ros2 --version 2>/dev/null || echo 'ok'))"
else
    fail "ros2 non trouvé après installation"
fi

# Ajouter au .bashrc si pas déjà fait
if ! grep -q "ros/jazzy" ~/.bashrc; then
    echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc
fi

# =============================================================================
# 3. SDK Unitree L2
# =============================================================================
step "Installation du SDK Unitree L2"
if [ ! -d "$SDK_DIR" ]; then
    git clone "$SDK_URL" "$SDK_DIR"
else
    warn "SDK déjà cloné dans $SDK_DIR"
fi

# Check
if [ -f "$SDK_DIR/unitree_lidar_sdk/lib/aarch64/libunilidar_sdk2.a" ]; then
    ok "SDK lib trouvée (aarch64)"
elif [ -f "$SDK_DIR/unitree_lidar_sdk/lib/x86_64/libunilidar_sdk2.a" ]; then
    ok "SDK lib trouvée (x86_64)"
else
    fail "SDK lib introuvable dans $SDK_DIR/unitree_lidar_sdk/lib/"
fi

if [ -f "$SDK_DIR/unitree_lidar_sdk/include/unitree_lidar_sdk.h" ]; then
    ok "SDK header trouvé"
else
    fail "SDK header introuvable"
fi

# Compiler le driver ROS2
step "Compilation du driver ROS2 Unitree"
cd "$SDK_DIR/unitree_lidar_ros2"
source /opt/ros/jazzy/setup.bash
colcon build

# Check
if [ -d "$SDK_DIR/unitree_lidar_ros2/install/unitree_lidar_ros2" ]; then
    source install/setup.bash
    ok "Driver ROS2 compilé"
    # Vérifier que le package est visible
    if ros2 pkg list 2>/dev/null | grep -q unitree_lidar_ros2; then
        ok "Package unitree_lidar_ros2 visible par ROS2"
    else
        fail "Package unitree_lidar_ros2 non visible par ROS2"
    fi
else
    fail "Compilation du driver ROS2 échouée"
fi

# Ajouter au .bashrc
if ! grep -q "unitree_lidar_ros2" ~/.bashrc; then
    echo "source $SDK_DIR/unitree_lidar_ros2/install/setup.bash" >> ~/.bashrc
fi

# =============================================================================
# 3b. FAST-LIO2 (SLAM LiDAR-Inertial)
# =============================================================================
step "Installation de FAST-LIO2"

# Dépendances
sudo apt install -y libeigen3-dev libpcl-dev ros-jazzy-pcl-ros

if [ ! -d "$FASTLIO_DIR" ]; then
    git clone "$FASTLIO_URL" "$FASTLIO_DIR" --recursive
else
    warn "FAST-LIO2 déjà cloné dans $FASTLIO_DIR"
fi

# Créer le workspace ROS2 pour FAST-LIO2
FASTLIO_WS="$HOME/fastlio_ws"
mkdir -p "$FASTLIO_WS/src"
if [ ! -L "$FASTLIO_WS/src/fast_lio" ]; then
    ln -sf "$FASTLIO_DIR" "$FASTLIO_WS/src/fast_lio"
fi

# Config + launch file Unitree L2 (copié depuis le repo)
step "Configuration spark-fast-lio pour Unitree L2"
SPARK_SHARE="$FASTLIO_WS/src/fast_lio/spark_fast_lio"
cp "$INSTALL_DIR/rpi5/config/unilidar.yaml" "$SPARK_SHARE/config/unilidar.yaml"
ok "Config unilidar.yaml copiée"

cat > "$SPARK_SHARE/launch/mapping_unilidar.launch.yaml" << 'LAUNCHYAML'
---
launch:
  - node:
      pkg: spark_fast_lio
      exec: spark_lio_mapping
      name: lio_mapping
      output: screen

      remap:
        - { from: 'lidar', to: '/unilidar/cloud' }
        - { from: 'imu',   to: '/unilidar/imu' }

      param:
        - name: "common.lidar_frame"
          value: "unilidar_lidar"
        - name: "common.imu_frame"
          value: "unilidar_imu"
        - name: "common.map_frame"
          value: "odom"

        - from: $(find-pkg-share spark_fast_lio)/config/unilidar.yaml
LAUNCHYAML
ok "Launch file mapping_unilidar.launch.yaml créé"

# Installer les dépendances ROS2
cd "$FASTLIO_WS"
source /opt/ros/jazzy/setup.bash
rosdep install --from-paths src --ignore-src -y 2>/dev/null || true

# Compiler (sourcer ROS2 + driver avant colcon build)
step "Compilation de FAST-LIO2"
cd "$FASTLIO_WS"
source /opt/ros/jazzy/setup.bash
source "$SDK_DIR/unitree_lidar_ros2/install/setup.bash" 2>/dev/null || true
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release -Wno-dev

# Check
if [ -d "$FASTLIO_WS/install/spark_fast_lio" ]; then
    source "$FASTLIO_WS/install/setup.bash"
    ok "spark-fast-lio compilé"
    if ros2 pkg list 2>/dev/null | grep -q spark_fast_lio; then
        ok "Package spark_fast_lio visible par ROS2"
    else
        fail "Package spark_fast_lio non visible"
    fi
else
    fail "Compilation de spark-fast-lio échouée"
fi

# Ajouter au .bashrc
if ! grep -q "fastlio_ws" ~/.bashrc; then
    echo "source $FASTLIO_WS/install/setup.bash" >> ~/.bashrc
fi

# =============================================================================
# 4. Projet LiDAR Scanner
# =============================================================================
step "Installation du projet LiDAR Scanner"
if [ ! -d "$INSTALL_DIR" ]; then
    git clone "$REPO_URL" "$INSTALL_DIR"
else
    warn "Projet déjà cloné dans $INSTALL_DIR — mise à jour"
    cd "$INSTALL_DIR" && git pull
fi

# Check
for f in rpi5/web_dashboard.py rpi5/static/index.html rpi5/lidar_mode.cpp rpi5/Makefile scripts/capture/scan_session.py; do
    if [ -f "$INSTALL_DIR/$f" ]; then
        ok "$f"
    else
        fail "$f manquant"
    fi
done

# Créer le dossier scans
mkdir -p "$SCAN_DIR"

# =============================================================================
# 5. Python venv + dépendances dashboard
# =============================================================================
step "Création du venv Python et installation des dépendances"
python3 -m venv --system-site-packages "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install fastapi uvicorn requests

# Check
for pkg in fastapi uvicorn requests; do
    if "$VENV_DIR/bin/python" -c "import $pkg" 2>/dev/null; then
        ok "Python: $pkg"
    else
        fail "Python: $pkg non installé"
    fi
done

# =============================================================================
# 6. Compilation de lidar_mode
# =============================================================================
step "Compilation de lidar_mode"
cd "$INSTALL_DIR/rpi5"
make SDK_DIR="$SDK_DIR" clean
make SDK_DIR="$SDK_DIR"
sudo make install

# Check
if [ -x /usr/local/bin/lidar_mode ]; then
    ok "lidar_mode installé dans /usr/local/bin/"
    # Vérifier qu'il s'exécute (sans LiDAR connecté, il échouera mais pas de segfault)
    if /usr/local/bin/lidar_mode 2>&1 | grep -q "Usage"; then
        ok "lidar_mode exécutable OK"
    else
        warn "lidar_mode exécutable mais sortie inattendue"
    fi
else
    fail "lidar_mode non installé"
fi

# =============================================================================
# 7. Configuration réseau — Ethernet pour LiDAR
# =============================================================================
step "Configuration réseau Ethernet (eth0 → LiDAR)"
NETPLAN_FILE="/etc/netplan/01-lidar.yaml"
if [ ! -f "$NETPLAN_FILE" ]; then
    sudo tee "$NETPLAN_FILE" > /dev/null << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 192.168.1.2/30
      optional: true
      dhcp4: no
      routes:
        - to: 192.168.1.62/32
          via: 192.168.1.2
EOF
    sudo netplan apply
else
    warn "Netplan déjà configuré ($NETPLAN_FILE)"
fi

# Check
if ip addr show eth0 2>/dev/null | grep -q "192.168.1.2"; then
    ok "eth0 configuré en 192.168.1.2"
else
    warn "eth0 pas encore en 192.168.1.2 (sera actif au prochain boot ou quand le câble est branché)"
fi

# =============================================================================
# 8. Service systemd — Dashboard
# =============================================================================
step "Installation du service systemd (dashboard)"

sudo tee /etc/systemd/system/lidar-dashboard.service > /dev/null << EOF
[Unit]
Description=LiDAR Scanner Dashboard
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR/rpi5
Environment=SCAN_DATA_DIR=$SCAN_DIR
ExecStart=/bin/bash -c "source /opt/ros/jazzy/setup.bash && source $SDK_DIR/unitree_lidar_ros2/install/setup.bash 2>/dev/null && source $FASTLIO_WS/install/setup.bash 2>/dev/null; $VENV_DIR/bin/python $INSTALL_DIR/rpi5/web_dashboard.py --port 8080"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable lidar-dashboard
sudo systemctl start lidar-dashboard

# Check
sleep 2
if systemctl is-active --quiet lidar-dashboard; then
    ok "Service lidar-dashboard actif"
    # Vérifier que le port 8080 répond
    if curl -sf http://localhost:8080/ > /dev/null 2>&1; then
        ok "Dashboard accessible sur :8080"
    else
        warn "Dashboard démarré mais :8080 ne répond pas encore (peut prendre quelques secondes)"
    fi
else
    fail "Service lidar-dashboard non actif"
    echo "    Logs: sudo journalctl -u lidar-dashboard -n 20"
fi

# =============================================================================
# 9. Service systemd — Driver LiDAR ROS2
# =============================================================================
step "Installation du service systemd (driver LiDAR ROS2)"

sudo tee /etc/systemd/system/lidar-driver.service > /dev/null << EOF
[Unit]
Description=Unitree L2 LiDAR ROS2 Driver
After=network.target
Before=lidar-dashboard.service

[Service]
Type=simple
User=$USER
ExecStart=/bin/bash -c "source /opt/ros/jazzy/setup.bash && source $SDK_DIR/unitree_lidar_ros2/install/setup.bash && ros2 launch unitree_lidar_ros2 launch.py"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable lidar-driver
sudo systemctl start lidar-driver

# Check
sleep 3
if systemctl is-active --quiet lidar-driver; then
    ok "Service lidar-driver actif"
    # Vérifier les topics ROS2
    sleep 2
    if ros2 topic list 2>/dev/null | grep -q "/unilidar/cloud"; then
        ok "Topic /unilidar/cloud publié"
    else
        warn "Topic /unilidar/cloud pas encore visible (LiDAR branché ?)"
    fi
else
    warn "Service lidar-driver non actif (normal si le LiDAR n'est pas branché)"
fi

# =============================================================================
# 10. Service systemd — FAST-LIO2 (SLAM)
# =============================================================================
step "Installation du service systemd (FAST-LIO2 SLAM)"

sudo tee /etc/systemd/system/lidar-slam.service > /dev/null << EOF
[Unit]
Description=FAST-LIO2 SLAM (LiDAR-Inertial Odometry)
After=lidar-driver.service
Requires=lidar-driver.service

[Service]
Type=simple
User=$USER
ExecStart=/bin/bash -c "source /opt/ros/jazzy/setup.bash && source $SDK_DIR/unitree_lidar_ros2/install/setup.bash && source $FASTLIO_WS/install/setup.bash && ros2 launch spark_fast_lio mapping_unilidar.launch.yaml"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable lidar-slam

# Ne pas démarrer automatiquement — le SLAM consomme du CPU
# Il sera lancé par le dashboard quand un scan démarre
warn "Service lidar-slam installé mais non démarré (lancé à la demande via le dashboard)"

# Check
if systemctl is-enabled --quiet lidar-slam; then
    ok "Service lidar-slam activé"
else
    fail "Service lidar-slam non activé"
fi

# =============================================================================
# 11. Sudoers pour systemctl sans mot de passe (dashboard)
# =============================================================================
step "Configuration sudoers pour le dashboard"
SUDOERS_FILE="/etc/sudoers.d/lidar-scanner"
sudo tee "$SUDOERS_FILE" > /dev/null << EOF
$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start lidar-slam
$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop lidar-slam
$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lidar-slam
$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lidar-dashboard
$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lidar-driver
EOF
sudo chmod 440 "$SUDOERS_FILE"

# Check
if sudo -n systemctl status lidar-slam 2>/dev/null; then
    ok "Sudoers configuré"
else
    ok "Sudoers installé"
fi

# =============================================================================
# 12. Clé SSH (optionnel — pour déploiement depuis le Mac)
# =============================================================================
step "Clé SSH"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
    ok "Clé SSH générée"
    echo "    Pour accès sans mot de passe depuis le Mac :"
    echo "    ssh-copy-id $USER@$(hostname).local"
else
    ok "Clé SSH déjà existante"
fi

# =============================================================================
# Résumé
# =============================================================================
echo ""
echo -e "${GREEN}=============================================${NC}"
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}  Installation terminée sans erreur !${NC}"
else
    echo -e "${YELLOW}  Installation terminée avec ${#ERRORS[@]} erreur(s) :${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "    ${RED}✗ $err${NC}"
    done
fi
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "  Dashboard  : http://$(hostname -I | awk '{print $1}'):8080"
echo "  Scans      : $SCAN_DIR"
echo "  Logs       : sudo journalctl -u lidar-dashboard -f"
echo "               sudo journalctl -u lidar-driver -f"
echo ""
echo "  Services :"
echo "    lidar-driver    — driver ROS2 Unitree L2 (auto-start)"
echo "    lidar-dashboard — interface web (auto-start)"
echo ""
echo "  Pour redémarrer :"
echo "    sudo systemctl restart lidar-driver"
echo "    sudo systemctl restart lidar-dashboard"
echo ""
