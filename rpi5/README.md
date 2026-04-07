# Configuration Raspberry Pi 5

## Architecture réseau (confirmée par test)

```
                    ┌──────────────────┐
                    │   Raspberry Pi 5 │
                    │                  │
Unitree L2 ◀══════▶│ eth0  (statique) │  Ethernet → données LiDAR
                    │ 192.168.1.2/30   │
                    │                  │
GoPro Max  ◀──wifi─▶│ wlan0 (client)   │  WiFi → contrôle + download photos
                    │ 10.5.5.x        │  SSID: "GoPro MAX"
                    │                  │
Téléphone  ◀──wifi─▶│ ap0   (hotspot)  │  WiFi → monitoring interface web
                    │ 192.168.4.1     │  SSID: "LidarScanner"
                    └──────────────────┘

  wlan0 + ap0 = même puce WiFi, dual STA+AP (testé OK)
  Contrainte : les deux sur le même canal WiFi
  Pas de dongle USB nécessaire!
```

## Installation

### OS
```bash
# Flasher Ubuntu 24.04 Server (ARM64) sur SSD NVMe (via HAT)
# Les cartes SD sont trop lentes pour les rosbags volumineux
```

### ROS2
```bash
sudo apt install ros-jazzy-desktop
echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
```

### SDK Unitree L2
```bash
git clone https://github.com/unitreerobotics/unilidar_sdk2.git
cd unilidar_sdk2 && mkdir build && cd build
cmake .. && make -j4

# Driver ROS2
cd ~
git clone https://github.com/unitreerobotics/unitree_lidar_ros2.git
cd unitree_lidar_ros2
colcon build
```

### Python (contrôle GoPro)
```bash
pip install goprocam requests
```

## Réseau

### Ethernet → Unitree L2
```yaml
# /etc/netplan/01-lidar.yaml
network:
  ethernets:
    eth0:
      addresses: [192.168.1.10/24]
      dhcp4: false
```

### WiFi → GoPro Max
```bash
# Connecter au WiFi de la GoPro (faire une fois, sera mémorisé)
nmcli device wifi connect "GPxxxxxxxx" password "xxxxxxxx"

# Vérifier la connexion
curl http://10.5.5.9/gp/gpControl/status
```

Le SSID et mot de passe WiFi de la GoPro Max se trouvent dans :
**GoPro > Préférences > Connexions > Infos caméra**

## Dashboard web (monitoring + contrôle)

Interface web accessible depuis le téléphone via le hotspot `LidarScanner`.

### Installation
```bash
pip install fastapi uvicorn

# Copier le service systemd
sudo cp ~/lidar-scanner/rpi5/lidar-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable lidar-dashboard
sudo systemctl start lidar-dashboard
```

### Accès
```
http://192.168.4.1:8080   (via WiFi "LidarScanner")
```

### Fonctionnalités
- Stockage disque (libre/utilisé + taille des scans)
- Batterie (si UPS HAT présent)
- État réseau : eth0/LiDAR, wlan0/GoPro, ap0/hotspot
- Lancer / pause / arrêter un scan
- Liste des sessions passées

### Logs
```bash
sudo journalctl -u lidar-dashboard -f
```

## Capture

### Session complète (LiDAR + GoPro synchronisés)
```bash
# 1. Lancer le driver LiDAR
ros2 launch unitree_lidar_ros2 launch.py &

# 2. Connecter au WiFi GoPro
nmcli device wifi connect "GPxxxxxxxx"

# 3. Lancer la session de scan
python scripts/capture/scan_session.py \
    --name batiment_01 \
    --interval 2 \
    --data-dir ~/scans/

# Ctrl+C pour arrêter → sauvegarde automatique du log
```

### GoPro seule
```bash
# Prendre une photo
python scripts/capture/gopro_control.py --mode photo --output ~/photos/

# Télécharger toutes les photos
python scripts/capture/gopro_control.py --mode download --output ~/photos/

# Status de la caméra
python scripts/capture/gopro_control.py --mode status
```

### Rosbag seul
```bash
ros2 bag record /unitree_lidar/cloud /unitree_lidar/imu \
    -o ~/scans/scan_$(date +%Y%m%d_%H%M%S)
```

## Transfert vers MacBook

Après la session, transférer les données via un réseau local :
```bash
# Connecter le RPi5 à un réseau WiFi classique (déconnecter la GoPro d'abord)
nmcli device wifi connect "MonWiFi" password "xxx"

# Transférer
rsync -avz --progress ~/scans/ simon@macbook.local:"~/DEV/LIDAR SCANNER/data/raw/"
```

Ou directement via câble USB/Ethernet entre le RPi5 et le MacBook.
