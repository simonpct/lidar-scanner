#!/usr/bin/env python3
"""
Colorisation d'un nuage de points LiDAR à partir de photos 360 equirectangulaires.

Usage:
    python colorize.py --cloud scan.laz --poses camera_poses_enu.json --photos photos_dir/ --output colorized.laz
"""

import argparse
import json
from pathlib import Path

import numpy as np
import laspy
from PIL import Image
from scipy.spatial import KDTree
from scipy.spatial.transform import Rotation


def project_to_equirectangular(points, camera_pos, camera_rot, img_width, img_height):
    """
    Projette des points 3D dans une image equirectangulaire 360.

    Args:
        points: (N, 3) array de points 3D
        camera_pos: (3,) position de la caméra
        camera_rot: Rotation (scipy) de la caméra, ou None pour identité
        img_width, img_height: dimensions de l'image equirectangulaire

    Returns:
        u, v: coordonnées pixel (N,) arrays
    """
    d = points - camera_pos

    # Transformer dans le repère caméra si rotation fournie
    if camera_rot is not None:
        d = camera_rot.inv().apply(d)

    norms = np.linalg.norm(d, axis=1, keepdims=True)
    norms[norms == 0] = 1e-10
    d = d / norms

    longitude = np.arctan2(d[:, 0], d[:, 2])
    latitude = np.arcsin(np.clip(d[:, 1], -1, 1))

    u = ((longitude / (2 * np.pi) + 0.5) * img_width).astype(int) % img_width
    v = ((0.5 - latitude / np.pi) * img_height).astype(int)
    v = np.clip(v, 0, img_height - 1)

    return u, v


def colorize_point_cloud(
    cloud_path: Path,
    poses_path: Path,
    photos_dir: Path,
    output_path: Path,
    k_cameras: int = 3,
    batch_size: int = 100_000,
):
    """
    Colorise un nuage de points en projetant chaque point dans les K caméras 360 les plus proches.

    Args:
        cloud_path: chemin vers le nuage .las/.laz
        poses_path: chemin vers le JSON des poses caméra (format ENU)
        photos_dir: dossier contenant les images equirectangulaires
        output_path: chemin de sortie .las/.laz
        k_cameras: nombre de caméras pour le blending
        batch_size: taille des batches pour le traitement (mémoire)
    """
    # Charger le nuage de points
    print(f"Chargement du nuage: {cloud_path}")
    las = laspy.read(str(cloud_path))
    points = np.vstack((las.x, las.y, las.z)).T
    n_points = len(points)
    print(f"  {n_points:,} points")

    # Charger les poses caméra (supporte les deux formats : ENU et synced)
    with open(poses_path) as f:
        poses_data = json.load(f)

    cameras = poses_data["cameras"]

    # Détecter le format (sync_timestamps.py ou gps_to_local.py)
    if "position" in cameras[0]:
        # Format sync_timestamps (avec rotation)
        cam_positions = np.array([c["position"] for c in cameras])
        cam_rotations = [
            Rotation.from_quat(c["rotation_quat_xyzw"]) if "rotation_quat_xyzw" in c else None
            for c in cameras
        ]
    else:
        # Format GPS/ENU (sans rotation)
        cam_positions = np.array([c["position_enu"] for c in cameras])
        cam_rotations = [None] * len(cameras)

    cam_images = [photos_dir / c["image"] for c in cameras]
    print(f"  {len(cameras)} caméras")

    # KD-tree des positions caméra
    cam_tree = KDTree(cam_positions)

    # Pré-charger les images (ou utiliser un cache si trop nombreuses)
    print("Chargement des images 360...")
    image_cache = {}

    def get_image(idx):
        if idx not in image_cache:
            img = Image.open(cam_images[idx])
            image_cache[idx] = np.array(img)
            # Limiter le cache à 20 images en mémoire
            if len(image_cache) > 20:
                oldest = next(iter(image_cache))
                del image_cache[oldest]
        return image_cache[idx]

    # Colorisation par batch
    colors = np.zeros((n_points, 3), dtype=np.float64)
    print(f"Colorisation en cours ({n_points:,} points, batches de {batch_size:,})...")

    for start in range(0, n_points, batch_size):
        end = min(start + batch_size, n_points)
        batch_points = points[start:end]
        batch_colors = np.zeros((end - start, 3), dtype=np.float64)

        # Trouver les K caméras les plus proches pour chaque point
        dists, indices = cam_tree.query(batch_points, k=k_cameras)

        # Pondération par inverse de la distance
        weights = 1.0 / (dists + 1e-6)
        weights_sum = weights.sum(axis=1, keepdims=True)
        weights = weights / weights_sum

        for k in range(k_cameras):
            cam_indices = indices[:, k]
            cam_weights = weights[:, k]

            # Grouper par caméra pour charger chaque image une seule fois
            unique_cams = np.unique(cam_indices)
            for cam_idx in unique_cams:
                mask = cam_indices == cam_idx
                if not mask.any():
                    continue

                img_array = get_image(cam_idx)
                img_h, img_w = img_array.shape[:2]

                u, v = project_to_equirectangular(
                    batch_points[mask], cam_positions[cam_idx],
                    cam_rotations[cam_idx], img_w, img_h
                )

                pixel_colors = img_array[v, u, :3].astype(np.float64)
                batch_colors[mask] += pixel_colors * cam_weights[mask, np.newaxis]

        colors[start:end] = batch_colors

        progress = min(100, int((end / n_points) * 100))
        print(f"  {progress}% ({end:,}/{n_points:,} points)", end="\r")

    print()
    colors = np.clip(colors, 0, 255).astype(np.uint16)

    # Écriture du nuage colorisé
    print(f"Sauvegarde: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Créer un nouveau fichier LAS avec les couleurs
    header = laspy.LasHeader(point_format=2, version="1.4")
    header.offsets = las.header.offsets
    header.scales = las.header.scales

    out_las = laspy.LasData(header)
    out_las.x = las.x
    out_las.y = las.y
    out_las.z = las.z
    out_las.red = colors[:, 0] * 256  # LAS stocke les couleurs en 16-bit
    out_las.green = colors[:, 1] * 256
    out_las.blue = colors[:, 2] * 256

    out_las.write(str(output_path))
    print(f"Terminé! {n_points:,} points colorisés -> {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Colorise un nuage de points LiDAR avec des photos 360"
    )
    parser.add_argument("--cloud", required=True, help="Nuage de points .las/.laz")
    parser.add_argument("--poses", required=True, help="Poses caméra JSON (format ENU)")
    parser.add_argument("--photos", required=True, help="Dossier des images 360")
    parser.add_argument("--output", required=True, help="Sortie .las/.laz colorisé")
    parser.add_argument(
        "--k-cameras", type=int, default=3, help="Nombre de caméras pour le blending"
    )
    parser.add_argument(
        "--batch-size", type=int, default=100_000, help="Taille des batches"
    )

    args = parser.parse_args()

    colorize_point_cloud(
        cloud_path=Path(args.cloud),
        poses_path=Path(args.poses),
        photos_dir=Path(args.photos),
        output_path=Path(args.output),
        k_cameras=args.k_cameras,
        batch_size=args.batch_size,
    )


if __name__ == "__main__":
    main()
