#!/usr/bin/env python3
"""
Applique les poses KISS-ICP aux scans bruts pour créer un nuage aligné.

Usage:
    python apply_poses.py \
        --bag ~/scans/cesi3/lidar/rosbag_cesi3 \
        --poses ~/scans/cesi3/rosbag_cesi3_poses.npy \
        --topic /unilidar/cloud \
        -o ~/scans/cesi3/cloud_aligned.ply

Prérequis: pip install numpy open3d (ou sur le Pi: rosbag2_py)
"""

import argparse
import struct
import sys
from pathlib import Path

import numpy as np


def read_rosbag_clouds(bag_path: str, topic: str):
    """Lit chaque scan PointCloud2 comme un array de points (N, 3)."""
    from rosbag2_py import SequentialReader, StorageOptions, ConverterOptions
    from rclpy.serialization import deserialize_message
    from sensor_msgs.msg import PointCloud2

    reader = SequentialReader()
    reader.open(
        StorageOptions(uri=bag_path, storage_id=""),
        ConverterOptions("cdr", "cdr"),
    )

    clouds = []
    while reader.has_next():
        t, data, _ = reader.read_next()
        if t != topic:
            continue

        msg = deserialize_message(data, PointCloud2)
        raw = bytes(msg.data)
        ps = msg.point_step
        n = msg.width * max(msg.height, 1)

        points = []
        for i in range(n):
            offset = i * ps
            if offset + 12 > len(raw):
                break
            x, y, z = struct.unpack_from("<fff", raw, offset)
            if abs(x) < 500 and abs(y) < 500 and abs(z) < 500 and (x != 0 or y != 0 or z != 0):
                points.append((x, y, z))

        clouds.append(np.array(points, dtype=np.float64))

    return clouds


def apply_poses_to_clouds(clouds, poses):
    """Transforme chaque scan par sa pose et fusionne."""
    all_points = []
    n = min(len(clouds), len(poses))
    print(f"  {n} scans à aligner ({len(clouds)} clouds, {len(poses)} poses)")

    for i in range(n):
        if len(clouds[i]) == 0:
            continue

        pose = poses[i]  # 4x4 matrix
        pts = clouds[i]

        # Appliquer la transformation: p' = R @ p + t
        R = pose[:3, :3]
        t = pose[:3, 3]
        transformed = (R @ pts.T).T + t

        # Sous-échantillonner pour limiter la taille (1 point sur 3)
        all_points.append(transformed[::3])

    return np.vstack(all_points)


def save_ply(points: np.ndarray, path: str):
    """Sauvegarde en PLY binaire."""
    n = len(points)
    header = f"""ply
format binary_little_endian 1.0
element vertex {n}
property float x
property float y
property float z
end_header
"""
    with open(path, "wb") as f:
        f.write(header.encode())
        points.astype(np.float32).tofile(f)


def main():
    parser = argparse.ArgumentParser(description="Applique les poses KISS-ICP au nuage brut")
    parser.add_argument("--bag", required=True, help="Chemin vers le rosbag")
    parser.add_argument("--poses", required=True, help="Fichier poses .npy de KISS-ICP")
    parser.add_argument("--topic", default="/unilidar/cloud")
    parser.add_argument("-o", "--output", required=True, help="Fichier PLY de sortie")

    args = parser.parse_args()

    print(f"Chargement des poses: {args.poses}")
    poses = np.load(args.poses)
    print(f"  {len(poses)} poses chargées")

    print(f"Lecture du rosbag: {args.bag}")
    clouds = read_rosbag_clouds(args.bag, args.topic)
    print(f"  {len(clouds)} scans lus")

    print("Alignement des scans...")
    aligned = apply_poses_to_clouds(clouds, poses)
    print(f"  {len(aligned)} points total")

    print(f"Sauvegarde: {args.output}")
    save_ply(aligned, args.output)
    size_mb = Path(args.output).stat().st_size / 1e6
    print(f"  {size_mb:.1f} Mo")


if __name__ == "__main__":
    main()
