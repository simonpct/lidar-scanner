# Pipeline de colorisation - Guide détaillé

## Vue d'ensemble

```
LiDAR (.laz) + Photos 360 (.jpg)
         │              │
         ▼              ▼
    ┌─────────┐   ┌──────────┐
    │  SLAM   │   │ Extract  │
    │ FAST-LIO│   │ equirect │
    └────┬────┘   └────┬─────┘
         │              │
         ▼              ▼
    ┌──────────────────────────────────────┐
    │     SYNCHRONISATION PAR TIMESTAMP    │
    │  Interpoler pose SLAM au moment de   │
    │  chaque photo + appliquer offset     │
    │  fixe GoPro/LiDAR (10cm)            │
    └──────────────────┬───────────────────┘
                       │
                       ▼
    ┌──────────────────────────────────────┐
    │           COLORISATION               │
    │  Projection equirectangulaire +      │
    │  blending multi-caméra               │
    └──────────────────┬───────────────────┘
                       │
                       ▼
    ┌──────────────────────────────────────┐
    │         EXPORT & VISUALISATION       │
    │   .laz RGB / Potree / 3D Tiles       │
    └──────────────────────────────────────┘
```

## Setup physique (rig)

```
        ┌───────────┐
        │ Unitree L2│  ← sommet, FOV libre 360°
        └─────┬─────┘
              │ tige 10cm (offset fixe connu)
        ┌─────┴─────┐
        │ GoPro Max │  ← lentilles dégagées vers les côtés
        └─────┬─────┘
        [  CHÂSSIS  ]
```

La GoPro est **sous** le L2 : ses lentilles (faces avant/arrière) sont dégagées
vers les côtés. La tige fine + le puck L2 au-dessus ne masquent qu'une petite zone
haute, peu critique (les bâtiments sont sur les côtés et en bas).

L'offset physique entre les deux capteurs est **fixe et mesuré** (ex: `[0, 0, -0.10]` si la GoPro est 10cm en dessous).
Cela permet de déduire la pose de la caméra directement depuis la trajectoire SLAM :

```
Pose_camera(t) = Pose_lidar(t) + R(t) × offset_fixe
```

Où `R(t)` est la matrice de rotation du scanner à l'instant `t`.

## Étape 1 : Capture

### LiDAR
```bash
# Sur le Raspberry Pi 5 - enregistrement rosbag
ros2 launch unitree_lidar_ros2 launch.py
ros2 bag record /unitree_lidar/cloud /unitree_lidar/imu -o scan_batiment_01
```

### GoPro Max
- Mode **Photo 360** (pas vidéo)
- Intervalle : **Time Lapse 360 photo, 1 photo / 2 secondes** en marchant lentement (~1m/s = 1 photo tous les 2m)
- Exposition : **manuelle** si possible, sinon appliquer un equalization en post

### Synchronisation des horloges (CRITIQUE)
Deux options :
1. **NTP** : le RPi5 sert de serveur NTP local, synchroniser la GoPro dessus (si supporté) ou synchroniser les deux sur un serveur commun
2. **Clap temporel** : au début du scan, faire un mouvement brusque ou un flash détectable dans les deux flux. Permet de recaler les timestamps en post-traitement avec un décalage constant `Δt`

La GoPro enregistre l'heure dans l'EXIF (`DateTimeOriginal` + `SubSecTimeOriginal`).
Le rosbag a des timestamps ROS (horloge du RPi5).

## Étape 2 : Extraction et préparation

### SLAM → trajectoire + nuage
```bash
# SLAM offline avec FAST-LIO2
# Rejouer le rosbag à travers FAST-LIO2
ros2 bag play scan_batiment_01/
# FAST-LIO2 produit :
#   - Le nuage de points global consolidé (.pcd)
#   - La trajectoire (séquence de poses timestampées)
```

La trajectoire SLAM est une séquence de :
```
timestamp, x, y, z, qx, qy, qz, qw   (position + quaternion de rotation)
```

### Extraire les timestamps des photos
```bash
# Timestamp de chaque photo GoPro
exiftool -csv -DateTimeOriginal -SubSecTimeOriginal \
  data/raw/photos_360/*.jpg > data/raw/gps/photo_timestamps.csv
```

### Si vidéo .360
```bash
# 1. Exporter en equirectangular via GoPro Player
# 2. Extraire les frames
ffmpeg -i stitched.mp4 -vf "fps=0.5" -q:v 2 data/processed/equirectangular/frame_%04d.jpg

# Les timestamps des frames = timestamp_début + (n_frame / fps)
```

## Étape 3 : Synchronisation par timestamp

C'est le coeur de l'approche. Pour chaque photo 360 :

1. **Trouver le timestamp** de la photo (EXIF)
2. **Interpoler la pose SLAM** à cet instant (interpolation linéaire position + SLERP rotation)
3. **Appliquer l'offset fixe** GoPro/LiDAR en tenant compte de la rotation

```python
from scipy.spatial.transform import Rotation, Slerp
import numpy as np

def interpolate_pose(trajectory, photo_timestamp, time_offset=0.0):
    """
    Interpole la pose du scanner au moment de la photo.
    
    Args:
        trajectory: liste de (timestamp, position_xyz, quaternion_xyzw)
        photo_timestamp: timestamp EXIF de la photo (secondes)
        time_offset: décalage constant entre horloges GoPro/RPi5
    """
    t = photo_timestamp + time_offset
    
    # Trouver les deux poses encadrant le timestamp
    times = [p[0] for p in trajectory]
    idx = np.searchsorted(times, t) - 1
    idx = max(0, min(idx, len(times) - 2))
    
    t0, pos0, q0 = trajectory[idx]
    t1, pos1, q1 = trajectory[idx + 1]
    
    # Facteur d'interpolation
    alpha = (t - t0) / (t1 - t0) if t1 != t0 else 0.0
    alpha = np.clip(alpha, 0, 1)
    
    # Interpolation position (linéaire)
    position = pos0 + alpha * (pos1 - pos0)
    
    # Interpolation rotation (SLERP)
    rots = Rotation.from_quat([q0, q1])
    slerp = Slerp([0, 1], rots)
    rotation = slerp(alpha)
    
    return position, rotation


def apply_camera_offset(lidar_pos, lidar_rot, offset_in_lidar_frame):
    """
    Calcule la position de la GoPro à partir de la pose du LiDAR.
    
    Args:
        lidar_pos: position XYZ du LiDAR
        lidar_rot: Rotation (scipy) du LiDAR
        offset_in_lidar_frame: vecteur [dx, dy, dz] de LiDAR vers GoPro
                               ex: [0, 0, 0.10] si GoPro 10cm au-dessus
    """
    # L'offset est fixe dans le repère du scanner,
    # il faut le transformer dans le repère monde
    offset_world = lidar_rot.apply(offset_in_lidar_frame)
    camera_pos = lidar_pos + offset_world
    
    return camera_pos, lidar_rot  # même orientation (rig rigide)
```

### Avantages de cette approche vs GPS/COLMAP
| | Timestamp + offset | GPS + ICP | COLMAP |
|---|---|---|---|
| **Précision** | Très bonne (hérite du SLAM) | Moyenne (GPS ±2-5m) | Bonne mais lente |
| **Complexité** | Simple | Moyenne | Élevée |
| **Dépendances** | Synchro horloges | GPS intérieur = impossible | Images de qualité suffisante |
| **Intérieur** | Fonctionne | Ne fonctionne pas | Fonctionne |

## Étape 4 : Colorisation

### Mathématiques de la projection equirectangulaire

Pour projeter un point 3D dans une image 360 equirectangulaire :

```python
import numpy as np

def project_to_equirectangular(point_3d, camera_pos, camera_rot, img_width, img_height):
    """
    Projeter un point 3D dans une image equirectangulaire 360.
    
    Args:
        camera_rot: Rotation de la caméra (pour aligner les axes).
                    Transforme le vecteur monde → repère caméra.
    """
    # Vecteur du point dans le repère caméra
    d = point_3d - camera_pos
    d = camera_rot.inv().apply(d)  # monde → repère caméra
    d = d / np.linalg.norm(d)

    # Coordonnées sphériques
    longitude = np.arctan2(d[0], d[2])  # azimut
    latitude = np.arcsin(np.clip(d[1], -1, 1))  # élévation

    # Vers coordonnées pixel
    u = (longitude / (2 * np.pi) + 0.5) * img_width
    v = (0.5 - latitude / np.pi) * img_height

    return int(u) % img_width, int(v)
```

### Blending multi-caméra
Quand un point est visible depuis plusieurs caméras, on blend les couleurs pondérées par :
- **Distance** au point (plus proche = plus de poids)
- **Angle d'incidence** (face = plus de poids, rasant = moins)

### Vérification d'occultation
Avant d'assigner une couleur, vérifier que le point est réellement visible depuis la caméra (pas derrière un mur). Approche : depth buffer ou KD-tree.

## Étape 5 : Export et visualisation

### CloudCompare (QA)
```bash
# Ouvrir le nuage colorisé pour inspection visuelle
open -a CloudCompare data/processed/colorized/batiment_01_colorized.laz
```

### Potree (web)
```bash
# Convertir en format Potree pour visualisation web
PotreeConverter data/processed/colorized/batiment_01_colorized.laz \
  -o data/output/web/batiment_01/
```

### 3D Tiles (Cesium)
Pour intégration dans des viewers 3D web type Cesium ou deck.gl.

## Conseils pratiques

1. **Synchronisation temporelle** : c'est LE point critique. Investir du temps pour calibrer le décalage `Δt` entre les horloges. Un décalage de 0.5s à 1m/s = 50cm d'erreur de pose.
2. **Calibration du rig** : mesurer l'offset [dx, dy, dz] avec précision (pied à coulisse). L'orientation relative GoPro/LiDAR doit aussi être calibrée si la GoPro n'est pas parfaitement alignée.
3. **Conditions de lumière** : scanner par temps couvert pour éviter les ombres dures et les surexpositions
4. **Chevauchement** : assurer un bon recouvrement entre les photos 360 (1 photo tous les 2m max)
5. **Itérer** : commencer par un petit scan test (une pièce) avant de s'attaquer à un bâtiment complet
6. **Vérification** : coloriser un petit sous-ensemble et vérifier visuellement dans CloudCompare avant de lancer sur tout le nuage
