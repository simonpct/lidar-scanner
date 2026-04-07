# Guide Hardware

## Unitree L2 - Scanner LiDAR

### Spécifications
| Spec | Valeur |
|------|--------|
| Portée | ~30m (90% réflectivité) |
| Points/sec | ~240 000 pts/s |
| FOV | 360° horizontal, ~90° vertical |
| Précision | ±2cm à <10m |
| IMU | 6 axes (accéléro + gyro) |
| Poids | ~350g |
| Alimentation | 12V DC (10-15W) |
| Connectivité | Ethernet 100M (UDP) |
| SLAM embarqué | Oui (LiDAR-inertiel) |

### Connexion au Raspberry Pi 5
- Câble Ethernet direct entre le L2 et le RPi5 (le Pi a du Gigabit, largement suffisant)
- Le flux de données est en UDP propriétaire binaire
- **Alimentation séparée** : le L2 nécessite du 12V, le Pi ne peut pas l'alimenter
- Le SDK C++ compile sur ARM64/Linux (Ubuntu pour RPi)

### SDK et logiciels
- **SDK officiel** : `unitreerobotics/unilidar_sdk` et `unilidar_sdk2` sur GitHub
- **ROS2** : package `unitree_lidar_ros2` (Humble ou Iron)
- **SLAM recommandés** (meilleurs que le SLAM embarqué) :
  - **FAST-LIO2** - très utilisé avec le L2, temps réel
  - **LIO-SAM** - LiDAR-inertiel, via le driver ROS2
  - **Point-LIO** - robuste aux mouvements agressifs

### Formats de sortie
Le L2 envoie des paquets UDP bruts (XYZ + intensité + timestamp). Les formats standard (.pcd, .las, .ply) sont produits en aval par le SDK ou les outils de post-traitement.

---

## Raspberry Pi 5 (8GB)

### Rôle
- Capture et enregistrement des données LiDAR en temps réel
- Relay vers le MacBook si besoin (WiFi ou stockage local)
- Enregistrement en rosbag pour traitement offline

### Configuration recommandée
- **OS** : Ubuntu 24.04 Server (ARM64)
- **ROS2** : Iron ou Humble
- **Stockage** : SSD NVMe via HAT (les cartes SD sont trop lentes pour les gros flux)

### Limitations
- Le SLAM temps réel sur Pi 5 est marginal en performance
- Recommandé : capturer les données brutes sur le Pi, faire le SLAM sur le MacBook
- Architecture : `L2 → RPi5 (capture rosbag) → MacBook (SLAM offline)`

### Alimentation terrain
- Batterie USB-C PD pour le Pi 5 (27W recommandé)
- Batterie 12V séparée pour le Unitree L2
- Ou une batterie V-mount avec sorties multiples

---

## GoPro Max

### Spécifications utiles
| Spec | Valeur |
|------|--------|
| Résolution 360 photo | 16.6MP (5760x2880) equirectangular |
| Format vidéo | `.360` (dual-lens H.265) |
| Format photo | `.jpg` equirectangular |
| GPS | Intégré (dans métadonnées EXIF/GPMF) |
| Télémétrie | GPMF (GoPro Metadata Format) |

### Mode recommandé
**Photos 360** plutôt que vidéo :
- Déjà en format equirectangular (pas de stitching nécessaire)
- GPS dans chaque EXIF
- Pipeline beaucoup plus simple
- Prendre une photo tous les 1-2 mètres de déplacement

### Si vidéo .360 nécessaire
1. Exporter en equirectangular MP4 via **GoPro Player** (macOS, gratuit)
2. Extraire les frames avec FFmpeg :
   ```bash
   ffmpeg -i stitched_video.mp4 -vf "fps=1" -q:v 2 frames/frame_%04d.jpg
   ```

### Extraction GPS
```bash
# GPS depuis les photos individuelles
exiftool -GPSLatitude -GPSLongitude -GPSAltitude photo_360.jpg

# Track GPS complet depuis une vidéo
gopro2gpx video.mp4 output_track
```

---

## Setup terrain complet

```
┌─────────────────┐     Ethernet      ┌──────────────┐
│   Unitree L2    │───────────────────▶│  Raspberry   │
│   (12V battery) │    UDP stream      │  Pi 5 (8GB)  │
└─────────────────┘                    │  + SSD NVMe  │
                                       │  (rosbag)    │
┌─────────────────┐                    └──────┬───────┘
│   GoPro Max     │                           │
│   (photo 360    │                      WiFi │ ou
│    tous les 2m) │                    stockage│local
└─────────────────┘                           │
                                       ┌──────▼───────┐
                                       │  MacBook M4  │
                                       │  (SLAM +     │
                                       │  colorisation)│
                                       └──────────────┘
```
