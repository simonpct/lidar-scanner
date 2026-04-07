#!/usr/bin/env python3
"""
Extraction des coordonnées GPS depuis les photos 360 GoPro Max.
Produit un fichier CSV avec les poses caméra (lat, lon, alt, fichier image).
"""

import csv
import subprocess
import json
import sys
from pathlib import Path


def extract_gps_from_photos(photos_dir: Path, output_csv: Path):
    """Extrait les coordonnées GPS de toutes les photos JPG via exiftool."""
    photos = sorted(photos_dir.glob("*.jpg")) + sorted(photos_dir.glob("*.JPG"))

    if not photos:
        print(f"Aucune photo trouvée dans {photos_dir}")
        sys.exit(1)

    print(f"Extraction GPS de {len(photos)} photos...")

    # exiftool en mode JSON pour un parsing facile
    result = subprocess.run(
        [
            "exiftool",
            "-json",
            "-GPSLatitude",
            "-GPSLongitude",
            "-GPSAltitude",
            "-DateTimeOriginal",
            "-n",  # format numérique (pas deg/min/sec)
        ]
        + [str(p) for p in photos],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"Erreur exiftool: {result.stderr}")
        sys.exit(1)

    data = json.loads(result.stdout)

    # Écriture CSV
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(output_csv, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["filename", "latitude", "longitude", "altitude", "datetime"])

        count = 0
        for entry in data:
            lat = entry.get("GPSLatitude")
            lon = entry.get("GPSLongitude")
            alt = entry.get("GPSAltitude", 0.0)
            dt = entry.get("DateTimeOriginal", "")
            filename = Path(entry.get("SourceFile", "")).name

            if lat is not None and lon is not None:
                writer.writerow([filename, lat, lon, alt, dt])
                count += 1

    print(f"{count}/{len(photos)} photos avec GPS -> {output_csv}")


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parent.parent.parent
    photos_dir = project_root / "data" / "raw" / "photos_360"
    output_csv = project_root / "data" / "raw" / "gps" / "camera_poses.csv"

    extract_gps_from_photos(photos_dir, output_csv)
