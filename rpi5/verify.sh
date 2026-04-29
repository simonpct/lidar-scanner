#!/bin/bash
# =============================================================================
# LiDAR Scanner — Script de vérification post-installation
# Vérifie que tous les composants sont installés et fonctionnels
#
# Usage : bash ~/lidar-scanner/rpi5/verify.sh
# =============================================================================

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

ok()   { echo -e "  ${GREEN}✓ $1${NC}"; ((PASS++)); }
warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; ((WARN++)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; ((FAIL++)); }
section() { echo -e "\n${GREEN}━━━ $1 ━━━${NC}"; }

# =============================================================================
section "Système"
# =============================================================================

# Architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then ok "Architecture: $ARCH"
else warn "Architecture: $ARCH (attendu: aarch64)"; fi

# Ubuntu version
if grep -q "24.04" /etc/os-release 2>/dev/null; then ok "Ubuntu 24.04"
else warn "Ubuntu version: $(lsb_release -rs 2>/dev/null || echo 'inconnue')"; fi

# Outils de base
for cmd in g++ cmake git python3 curl pip3; do
    if command -v $cmd &>/dev/null; then ok "$cmd"
    else fail "$cmd non trouvé"; fi
done

# =============================================================================
section "ROS2 Jazzy"
# =============================================================================

if [ -d /opt/ros/jazzy ]; then ok "/opt/ros/jazzy existe"
else fail "ROS2 Jazzy non installé"; fi

source /opt/ros/jazzy/setup.bash 2>/dev/null
if command -v ros2 &>/dev/null; then ok "ros2 CLI disponible"
else fail "ros2 CLI non trouvé"; fi

# .bashrc
if grep -q "ros/jazzy" ~/.bashrc 2>/dev/null; then ok "ROS2 dans .bashrc"
else warn "ROS2 pas dans .bashrc"; fi

# =============================================================================
section "SDK Unitree L2"
# =============================================================================

SDK_DIR="$HOME/unilidar_sdk2"
if [ -d "$SDK_DIR" ]; then ok "SDK cloné"
else fail "SDK non trouvé dans $SDK_DIR"; fi

if [ -f "$SDK_DIR/unitree_lidar_sdk/lib/aarch64/libunilidar_sdk2.a" ]; then ok "SDK lib (aarch64)"
elif [ -f "$SDK_DIR/unitree_lidar_sdk/lib/x86_64/libunilidar_sdk2.a" ]; then ok "SDK lib (x86_64)"
else fail "SDK lib introuvable"; fi

if [ -f "$SDK_DIR/unitree_lidar_sdk/include/unitree_lidar_sdk.h" ]; then ok "SDK header"
else fail "SDK header introuvable"; fi

# Driver ROS2
if [ -d "$SDK_DIR/unitree_lidar_ros2/install" ]; then
    source "$SDK_DIR/unitree_lidar_ros2/install/setup.bash" 2>/dev/null
    if ros2 pkg list 2>/dev/null | grep -q unitree_lidar_ros2; then ok "Driver ROS2 unitree_lidar_ros2"
    else fail "Package unitree_lidar_ros2 non visible"; fi
else fail "Driver ROS2 non compilé"; fi

# =============================================================================
section "FAST-LIO2 (SLAM)"
# =============================================================================

FASTLIO_WS="$HOME/fastlio_ws"
if [ -d "$FASTLIO_WS/install/spark_fast_lio" ]; then
    source "$FASTLIO_WS/install/setup.bash" 2>/dev/null
    ok "spark_fast_lio compilé"
    if ros2 pkg list 2>/dev/null | grep -q spark_fast_lio; then ok "Package spark_fast_lio visible"
    else fail "Package spark_fast_lio non visible"; fi
else fail "spark_fast_lio non compilé dans $FASTLIO_WS"; fi

# Config Unitree L2
SLAM_CONFIG="$FASTLIO_WS/install/spark_fast_lio/share/spark_fast_lio/config/unilidar.yaml"
if [ -f "$SLAM_CONFIG" ]; then ok "Config unilidar.yaml"
else warn "Config SLAM unilidar.yaml manquante"; fi

SLAM_LAUNCH="$FASTLIO_WS/install/spark_fast_lio/share/spark_fast_lio/launch/mapping_unilidar.launch.yaml"
if [ -f "$SLAM_LAUNCH" ]; then ok "Launch mapping_unilidar.launch.yaml"
else warn "Launch file SLAM manquant"; fi

# =============================================================================
section "Projet LiDAR Scanner"
# =============================================================================

INSTALL_DIR="$HOME/lidar-scanner"
if [ -d "$INSTALL_DIR" ]; then ok "Projet cloné"
else fail "Projet non trouvé dans $INSTALL_DIR"; fi

for f in rpi5/web_dashboard.py rpi5/static/index.html rpi5/lidar_mode.cpp rpi5/Makefile scripts/capture/scan_session.py scripts/capture/gopro_control.py; do
    if [ -f "$INSTALL_DIR/$f" ]; then ok "$f"
    else fail "$f manquant"; fi
done

# lidar_mode binaire
if [ -x /usr/local/bin/lidar_mode ]; then
    ok "lidar_mode installé"
    if /usr/local/bin/lidar_mode 2>&1 | grep -q "Usage"; then ok "lidar_mode exécutable"
    else warn "lidar_mode sortie inattendue"; fi
else fail "lidar_mode non installé"; fi

# =============================================================================
section "Python venv"
# =============================================================================

VENV="$INSTALL_DIR/rpi5/.venv"
if [ -d "$VENV" ]; then ok "venv existe"
else fail "venv non trouvé"; fi

for pkg in fastapi uvicorn requests; do
    if "$VENV/bin/python" -c "import $pkg" 2>/dev/null; then ok "Python: $pkg"
    else fail "Python: $pkg manquant"; fi
done

# rosbag2_py accessible
if "$VENV/bin/python" -c "import rosbag2_py" 2>/dev/null; then ok "Python: rosbag2_py (via system-site-packages)"
else warn "Python: rosbag2_py non accessible (snapshots ne fonctionneront pas)"; fi

# =============================================================================
section "Réseau"
# =============================================================================

# eth0
if ip addr show eth0 2>/dev/null | grep -q "192.168.1.2"; then ok "eth0: 192.168.1.2"
else warn "eth0 pas en 192.168.1.2 (LiDAR non branché ?)"; fi

# Netplan
if [ -f /etc/netplan/01-lidar.yaml ]; then ok "Netplan configuré"
else warn "Netplan non configuré"; fi

# =============================================================================
section "Services systemd"
# =============================================================================

for svc in lidar-dashboard lidar-driver lidar-slam foxglove-bridge; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc: activé + en cours"
        else
            if [ "$svc" = "lidar-slam" ] || [ "$svc" = "foxglove-bridge" ]; then
                ok "$svc: activé (démarré à la demande)"
            else
                warn "$svc: activé mais pas en cours"
            fi
        fi
    else
        fail "$svc: non activé"
    fi
done

# Dashboard accessible
if curl -sf http://localhost:8080/ > /dev/null 2>&1; then ok "Dashboard :8080 accessible"
else warn "Dashboard :8080 non accessible"; fi

# Metrics endpoint
if curl -sf http://localhost:8080/metrics > /dev/null 2>&1; then ok "Endpoint /metrics accessible"
else warn "Endpoint /metrics non accessible"; fi

# =============================================================================
section "Monitoring"
# =============================================================================

if systemctl is-active --quiet prometheus-node-exporter 2>/dev/null; then ok "node_exporter actif"
else warn "node_exporter non actif"; fi

if systemctl is-active --quiet prometheus 2>/dev/null; then ok "Prometheus actif"
else warn "Prometheus non actif"; fi

# =============================================================================
section "ROS2 Topics (si driver en cours)"
# =============================================================================

if ros2 topic list 2>/dev/null | grep -q "/unilidar/cloud"; then
    ok "Topic /unilidar/cloud"
else
    warn "/unilidar/cloud non publié (LiDAR branché ? driver lancé ?)"
fi

if ros2 topic list 2>/dev/null | grep -q "/unilidar/imu"; then
    ok "Topic /unilidar/imu"
else
    warn "/unilidar/imu non publié"
fi

if ros2 topic list 2>/dev/null | grep -q "/odometry"; then
    ok "Topic /odometry (SLAM actif)"
else
    warn "/odometry non publié (SLAM pas en cours, normal si pas de scan)"
fi

# =============================================================================
section "Sudoers"
# =============================================================================

if sudo -n systemctl status lidar-slam &>/dev/null; then ok "sudo systemctl sans mot de passe"
else warn "sudo systemctl nécessite un mot de passe (le dashboard ne pourra pas démarrer le SLAM)"; fi

# =============================================================================
section "SSH"
# =============================================================================

if [ -f "$HOME/.ssh/id_ed25519" ]; then ok "Clé SSH ed25519"
elif [ -f "$HOME/.ssh/id_rsa" ]; then ok "Clé SSH RSA"
else warn "Pas de clé SSH"; fi

# =============================================================================
# Résumé
# =============================================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✓ $PASS${NC}  ${YELLOW}⚠ $WARN${NC}  ${RED}✗ $FAIL${NC}"
if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}Installation OK !${NC}"
else
    echo -e "  ${RED}$FAIL problème(s) détecté(s)${NC}"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

exit $FAIL
