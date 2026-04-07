#!/usr/bin/env python3
"""
Synchronisation des poses caméra GoPro avec la trajectoire SLAM du LiDAR.

Interpole la pose du scanner au timestamp de chaque photo 360,
puis applique l'offset fixe GoPro/LiDAR pour obtenir la pose caméra.

Usage:
    python sync_timestamps.py \
        --trajectory slam_trajectory.csv \
        --photos data/raw/photos_360/ \
        --offset 0 0 0.10 \
        --time-offset 0.0 \
        --output data/processed/camera_poses_synced.json
"""

import argparse
import csv
import json
import subprocess
from datetime import datetime
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation, Slerp


def load_slam_trajectory(trajectory_path: Path):
    """
    Charge la trajectoire SLAM depuis un CSV.
    Format attendu: timestamp, x, y, z, qx, qy, qz, qw
    """
    trajectory = []
    with open(trajectory_path) as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            t = float(row[0])
            pos = np.array([float(row[1]), float(row[2]), float(row[3])])
            quat = np.array(
                [float(row[4]), float(row[5]), float(row[6]), float(row[7])]
            )
            trajectory.append((t, pos, quat))
    return trajectory


def extract_photo_timestamps(photos_dir: Path):
    """
    Extrait les timestamps EXIF des photos GoPro Max.
    Retourne une liste de (filename, timestamp_seconds).
    """
    photos = sorted(photos_dir.glob("*.jpg")) + sorted(photos_dir.glob("*.JPG"))
    if not photos:
        raise FileNotFoundError(f"Aucune photo dans {photos_dir}")

    result = subprocess.run(
        [
            "exiftool",
            "-json",
            "-DateTimeOriginal",
            "-SubSecTimeOriginal",
            "-n",
        ]
        + [str(p) for p in photos],
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)

    timestamps = []
    for entry in data:
        filename = Path(entry["SourceFile"]).name
        dt_str = entry.get("DateTimeOriginal", "")
        subsec = entry.get("SubSecTimeOriginal", "0")

        if not dt_str:
            continue

        # Parser "2024:03:15 14:30:22" + subsec
        dt = datetime.strptime(dt_str, "%Y:%m:%d %H:%M:%S")
        t = dt.timestamp() + float(subsec) / 100.0
        timestamps.append((filename, t))

    return timestamps


def interpolate_pose(trajectory, target_time):
    """
    Interpole la pose SLAM (position + rotation) au timestamp donné.
    Interpolation linéaire pour la position, SLERP pour la rotation.
    """
    times = [p[0] for p in trajectory]
    idx = int(np.searchsorted(times, target_time)) - 1
    idx = max(0, min(idx, len(times) - 2))

    t0, pos0, q0 = trajectory[idx]
    t1, pos1, q1 = trajectory[idx + 1]

    # Facteur d'interpolation
    dt = t1 - t0
    alpha = (target_time - t0) / dt if dt > 0 else 0.0
    alpha = float(np.clip(alpha, 0, 1))

    # Position : interpolation linéaire
    position = pos0 + alpha * (pos1 - pos0)

    # Rotation : SLERP
    rots = Rotation.from_quat([q0, q1])
    slerp = Slerp([0, 1], rots)
    rotation = slerp(alpha)

    return position, rotation


def apply_camera_offset(lidar_pos, lidar_rot, offset):
    """
    Calcule la pose de la GoPro depuis la pose du LiDAR + offset fixe.

    L'offset est exprimé dans le repère du scanner (ex: [0, 0, 0.10]
    si la GoPro est 10cm au-dessus du LiDAR).
    """
    offset_world = lidar_rot.apply(offset)
    camera_pos = lidar_pos + offset_world
    return camera_pos, lidar_rot


def sync_poses(
    trajectory_path: Path,
    photos_dir: Path,
    offset: np.ndarray,
    time_offset: float,
    output_path: Path,
):
    """Pipeline complète de synchronisation."""

    print(f"Chargement trajectoire SLAM: {trajectory_path}")
    trajectory = load_slam_trajectory(trajectory_path)
    print(f"  {len(trajectory)} poses, durée: {trajectory[-1][0] - trajectory[0][0]:.1f}s")

    traj_start = trajectory[0][0]
    traj_end = trajectory[-1][0]

    print(f"Extraction timestamps photos: {photos_dir}")
    photo_timestamps = extract_photo_timestamps(photos_dir)
    print(f"  {len(photo_timestamps)} photos")

    print(f"Offset GoPro/LiDAR: {offset}")
    print(f"Décalage temporel: {time_offset}s")

    cameras = []
    skipped = 0
    for filename, photo_time in photo_timestamps:
        t = photo_time + time_offset

        # Vérifier que le timestamp est dans la plage de la trajectoire
        if t < traj_start or t > traj_end:
            skipped += 1
            continue

        lidar_pos, lidar_rot = interpolate_pose(trajectory, t)
        cam_pos, cam_rot = apply_camera_offset(lidar_pos, lidar_rot, offset)

        cameras.append(
            {
                "image": filename,
                "timestamp": photo_time,
                "position": cam_pos.tolist(),
                "rotation_quat_xyzw": cam_rot.as_quat().tolist(),
                "lidar_position": lidar_pos.tolist(),
            }
        )

    if skipped:
        print(f"  {skipped} photos hors plage trajectoire (ignorées)")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(
            {
                "method": "slam_timestamp_sync",
                "offset_lidar_to_camera": offset.tolist(),
                "time_offset_seconds": time_offset,
                "trajectory_file": str(trajectory_path),
                "cameras": cameras,
            },
            f,
            indent=2,
        )

    print(f"\n{len(cameras)} poses caméra synchronisées -> {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Synchronise les poses caméra GoPro avec la trajectoire SLAM"
    )
    parser.add_argument(
        "--trajectory", required=True, help="Trajectoire SLAM (CSV: t,x,y,z,qx,qy,qz,qw)"
    )
    parser.add_argument("--photos", required=True, help="Dossier des photos 360")
    parser.add_argument(
        "--offset",
        nargs=3,
        type=float,
        default=[0, 0, 0.10],
        help="Offset [dx dy dz] du LiDAR vers la GoPro en mètres (défaut: 0 0 0.10)",
    )
    parser.add_argument(
        "--time-offset",
        type=float,
        default=0.0,
        help="Décalage temporel GoPro→LiDAR en secondes (défaut: 0)",
    )
    parser.add_argument(
        "--output", required=True, help="Sortie JSON des poses caméra"
    )

    args = parser.parse_args()

    sync_poses(
        trajectory_path=Path(args.trajectory),
        photos_dir=Path(args.photos),
        offset=np.array(args.offset),
        time_offset=args.time_offset,
        output_path=Path(args.output),
    )


if __name__ == "__main__":
    main()
