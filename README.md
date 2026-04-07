# LiDAR 3D Scanner - Pipeline de numérisation de bâtiments

Pipeline complète pour scanner des bâtiments en 3D, combiner les données LiDAR avec des photos 360, et produire des modèles 3D colorisés.

## Matériel

| Composant | Modèle | Rôle |
|-----------|--------|------|
| Scanner LiDAR | **Unitree L2** | Capture des nuages de points (240k pts/s, portée 30m, précision ±2cm) |
| Contrôleur terrain | **Raspberry Pi 5 (8GB)** | Acquisition temps réel, enregistrement des données |
| Caméra 360 | **GoPro Max** | Photos/vidéos 360 pour colorisation (5760x2880 equirectangular) |
| Post-traitement | **MacBook M4** | SLAM, colorisation, visualisation |

## Pipeline

```
┌─────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  1. CAPTURE  │───▶│  2. EXTRACT  │───▶│  3. ALIGN    │───▶│ 4. COLORIZE  │───▶│ 5. VISUALIZE │
│             │    │              │    │              │    │              │    │              │
│ LiDAR + 360 │    │ Frames GPS   │    │ ICP/COLMAP   │    │ Projection   │    │ CloudCompare │
│ sur terrain  │    │ equirect.    │    │ registration │    │ equirect.    │    │ Potree/Web   │
└─────────────┘    └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

### Étape 1 - Capture terrain
- Scanner LiDAR via Unitree L2 connecté au RPi5 (Ethernet UDP)
- Photos 360 avec GoPro Max (mode photo 360 recommandé)
- GPS embarqué dans les métadonnées EXIF de la GoPro

### Étape 2 - Extraction
- Export des nuages de points bruts (.las/.laz)
- Extraction des frames equirectangulaires depuis les fichiers .360
- Extraction des tracks GPS via exiftool/gopro2gpx

### Étape 3 - Alignement
- Alignement initial via coordonnées GPS
- Raffinement via COLMAP (SfM sur images 360) ou ICP (CloudCompare/Open3D)
- Transformation dans un repère commun

### Étape 4 - Colorisation
- Projection des points 3D dans les images equirectangulaires
- Échantillonnage RGB avec blending multi-caméra pondéré
- Vérification d'occultation

### Étape 5 - Visualisation
- QA dans CloudCompare
- Export LAZ avec RGB
- Visualisation web via Potree ou 3D Tiles

## Structure du projet

```
├── config/                  # Configuration et dépendances
├── data/
│   ├── raw/                 # Données brutes
│   │   ├── lidar/           # Nuages de points bruts (.las, .laz, .e57)
│   │   ├── photos_360/      # Photos/vidéos GoPro Max (.360, .jpg)
│   │   └── gps/             # Tracks GPS (.gpx)
│   ├── processed/           # Données intermédiaires
│   │   ├── point_clouds/    # Nuages après SLAM (.las, .laz)
│   │   ├── equirectangular/ # Frames 360 extraites (.jpg)
│   │   └── colorized/       # Nuages colorisés (.las, .laz, .ply)
│   └── output/              # Résultats finaux
│       ├── models/          # Modèles 3D (.obj, .glb)
│       └── web/             # Visualisation web (Potree)
├── docs/                    # Documentation détaillée
├── rpi5/                    # Scripts et config pour le Raspberry Pi 5
└── scripts/
    ├── capture/             # Acquisition terrain
    ├── processing/          # SLAM et traitement
    ├── colorization/        # Pipeline de colorisation
    └── visualization/       # Outils de visualisation
```

## Installation rapide (macOS M4)

```bash
# Dépendances système
brew install cloudcompare pdal ffmpeg exiftool colmap

# Environnement Python
python3 -m venv .venv
source .venv/bin/activate
pip install -r config/requirements.txt
```

## Formats de données

| Étape | Format | Raison |
|-------|--------|--------|
| Capture LiDAR | `.e57` / `.las` | Standard scanner / Standard LiDAR |
| Photos 360 | `.jpg` equirectangular | Universel, EXIF GPS conservé |
| GPS | `.gpx` | Standard d'échange GPS |
| Traitement | `.laz` / `.ply` | Compressé / Facile avec Open3D |
| Sortie colorisée | `.las/.laz` avec RGB | Standard industrie |
| Web | Potree / 3D Tiles | Visualisation navigateur |
