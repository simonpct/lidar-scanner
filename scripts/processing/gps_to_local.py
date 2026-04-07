#!/usr/bin/env python3
"""
Conversion des coordonnées GPS (WGS84) vers un repère local ENU (Est-Nord-Up).
Nécessaire pour aligner les poses caméra avec le nuage de points LiDAR.
"""

import csv
import json
from pathlib import Path
import numpy as np
from pyproj import Transformer


def wgs84_to_enu(lats, lons, alts, ref_lat=None, ref_lon=None, ref_alt=None):
    """
    Convertit des coordonnées WGS84 en coordonnées locales ENU.

    Args:
        lats, lons, alts: arrays de coordonnées GPS
        ref_lat, ref_lon, ref_alt: point de référence (origine du repère local).
                                    Si None, utilise le premier point.
    Returns:
        positions_enu: array (N, 3) en mètres [Est, Nord, Up]
    """
    if ref_lat is None:
        ref_lat, ref_lon, ref_alt = lats[0], lons[0], alts[0]

    # WGS84 -> ECEF
    transformer_to_ecef = Transformer.from_crs("EPSG:4326", "EPSG:4978", always_xy=True)

    # Point de référence en ECEF
    ref_x, ref_y, ref_z = transformer_to_ecef.transform(ref_lon, ref_lat, ref_alt)

    # Tous les points en ECEF
    xs, ys, zs = transformer_to_ecef.transform(lons, lats, alts)

    # ECEF -> ENU (rotation locale)
    lat_rad = np.radians(ref_lat)
    lon_rad = np.radians(ref_lon)

    dx = xs - ref_x
    dy = ys - ref_y
    dz = zs - ref_z

    # Matrice de rotation ECEF -> ENU
    east = -np.sin(lon_rad) * dx + np.cos(lon_rad) * dy
    north = (
        -np.sin(lat_rad) * np.cos(lon_rad) * dx
        - np.sin(lat_rad) * np.sin(lon_rad) * dy
        + np.cos(lat_rad) * dz
    )
    up = (
        np.cos(lat_rad) * np.cos(lon_rad) * dx
        + np.cos(lat_rad) * np.sin(lon_rad) * dy
        + np.sin(lat_rad) * dz
    )

    return np.column_stack([east, north, up])


def convert_camera_poses(input_csv: Path, output_json: Path):
    """Lit les poses GPS et les convertit en coordonnées locales ENU."""
    filenames = []
    lats, lons, alts = [], [], []

    with open(input_csv) as f:
        reader = csv.DictReader(f)
        for row in reader:
            filenames.append(row["filename"])
            lats.append(float(row["latitude"]))
            lons.append(float(row["longitude"]))
            alts.append(float(row["altitude"]))

    lats = np.array(lats)
    lons = np.array(lons)
    alts = np.array(alts)

    positions_enu = wgs84_to_enu(lats, lons, alts)

    # Sauvegarde en JSON
    poses = []
    for i, name in enumerate(filenames):
        poses.append(
            {
                "image": name,
                "position_enu": positions_enu[i].tolist(),
                "gps": {"lat": lats[i], "lon": lons[i], "alt": alts[i]},
            }
        )

    output_json.parent.mkdir(parents=True, exist_ok=True)
    with open(output_json, "w") as f:
        json.dump(
            {
                "coordinate_system": "ENU",
                "reference_point": {
                    "lat": float(lats[0]),
                    "lon": float(lons[0]),
                    "alt": float(alts[0]),
                },
                "cameras": poses,
            },
            f,
            indent=2,
        )

    print(f"{len(poses)} poses converties -> {output_json}")


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parent.parent.parent
    input_csv = project_root / "data" / "raw" / "gps" / "camera_poses.csv"
    output_json = project_root / "data" / "processed" / "camera_poses_enu.json"

    convert_camera_poses(input_csv, output_json)
