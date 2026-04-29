#!/usr/bin/env python3
"""
Exporte le nuage de points d'un rosbag en PLY/PCD/LAS.

Usage (sur le Pi ou le Mac avec ROS2) :
    python export_cloud.py ~/scans/batiment_01/lidar/rosbag_batiment_01 -o cloud.ply
    python export_cloud.py ~/scans/batiment_01/lidar/rosbag_batiment_01 -o cloud.las
    python export_cloud.py ~/scans/batiment_01/lidar/rosbag_batiment_01 -o cloud.pcd

Topics supportés :
    /cloud_registered  — nuage SLAM (aligné, recommandé)
    /unilidar/cloud    — nuage brut (non aligné)
"""

import argparse
import struct
import sys
from pathlib import Path

import numpy as np


def read_rosbag(bag_path: str, topic: str):
    """Lit tous les messages PointCloud2 d'un topic dans un rosbag."""
    from rosbag2_py import SequentialReader, StorageOptions, ConverterOptions
    from rclpy.serialization import deserialize_message
    from sensor_msgs.msg import PointCloud2

    reader = SequentialReader()
    storage_options = StorageOptions(uri=bag_path, storage_id="")
    converter_options = ConverterOptions(
        input_serialization_format="cdr",
        output_serialization_format="cdr",
    )
    reader.open(storage_options, converter_options)

    all_points = []
    msg_count = 0

    while reader.has_next():
        t, data, _ = reader.read_next()
        if t != topic:
            continue

        msg = deserialize_message(data, PointCloud2)
        raw = bytes(msg.data)
        ps = msg.point_step
        n = msg.width * max(msg.height, 1)

        for i in range(n):
            offset = i * ps
            if offset + 16 > len(raw):
                break
            x = struct.unpack_from("<f", raw, offset)[0]
            y = struct.unpack_from("<f", raw, offset + 4)[0]
            z = struct.unpack_from("<f", raw, offset + 8)[0]
            intensity = struct.unpack_from("<f", raw, offset + 12)[0] if ps >= 16 else 0
            if abs(x) < 500 and abs(y) < 500 and abs(z) < 500 and (x != 0 or y != 0 or z != 0):
                all_points.append((x, y, z, intensity))

        msg_count += 1

    print(f"  {msg_count} messages lus, {len(all_points)} points extraits")
    return np.array(all_points, dtype=np.float32) if all_points else np.empty((0, 4), dtype=np.float32)


def save_ply(points: np.ndarray, path: str):
    """Sauvegarde en PLY (ASCII)."""
    n = len(points)
    with open(path, "w") as f:
        f.write("ply\n")
        f.write("format ascii 1.0\n")
        f.write(f"element vertex {n}\n")
        f.write("property float x\n")
        f.write("property float y\n")
        f.write("property float z\n")
        f.write("property float intensity\n")
        f.write("end_header\n")
        for p in points:
            f.write(f"{p[0]:.6f} {p[1]:.6f} {p[2]:.6f} {p[3]:.2f}\n")


def save_pcd(points: np.ndarray, path: str):
    """Sauvegarde en PCD (ASCII)."""
    n = len(points)
    with open(path, "w") as f:
        f.write("# .PCD v0.7 - Point Cloud Data\n")
        f.write("VERSION 0.7\n")
        f.write("FIELDS x y z intensity\n")
        f.write("SIZE 4 4 4 4\n")
        f.write("TYPE F F F F\n")
        f.write("COUNT 1 1 1 1\n")
        f.write(f"WIDTH {n}\n")
        f.write("HEIGHT 1\n")
        f.write("VIEWPOINT 0 0 0 1 0 0 0\n")
        f.write(f"POINTS {n}\n")
        f.write("DATA ascii\n")
        for p in points:
            f.write(f"{p[0]:.6f} {p[1]:.6f} {p[2]:.6f} {p[3]:.2f}\n")


def save_las(points: np.ndarray, path: str):
    """Sauvegarde en LAS."""
    try:
        import laspy
    except ImportError:
        print("Erreur: pip install laspy[laszip]")
        sys.exit(1)

    header = laspy.LasHeader(point_format=0, version="1.4")
    las = laspy.LasData(header)
    las.x = points[:, 0]
    las.y = points[:, 1]
    las.z = points[:, 2]
    las.intensity = (points[:, 3] * 256).astype(np.uint16)
    las.write(path)


def main():
    parser = argparse.ArgumentParser(description="Export rosbag point cloud")
    parser.add_argument("bag_path", help="Chemin vers le rosbag")
    parser.add_argument("-o", "--output", required=True, help="Fichier de sortie (.ply, .pcd, .las)")
    parser.add_argument(
        "--topic",
        default="/cloud_registered",
        help="Topic à exporter (défaut: /cloud_registered = SLAM)",
    )

    args = parser.parse_args()

    ext = Path(args.output).suffix.lower()
    if ext not in (".ply", ".pcd", ".las"):
        print(f"Format non supporté: {ext}. Utiliser .ply, .pcd ou .las")
        sys.exit(1)

    print(f"Lecture du rosbag: {args.bag_path}")
    print(f"  Topic: {args.topic}")
    points = read_rosbag(args.bag_path, args.topic)

    if len(points) == 0:
        print("Aucun point trouvé. Essayer --topic /unilidar/cloud pour les données brutes.")
        sys.exit(1)

    print(f"Export vers: {args.output} ({len(points)} points)")
    if ext == ".ply":
        save_ply(points, args.output)
    elif ext == ".pcd":
        save_pcd(points, args.output)
    elif ext == ".las":
        save_las(points, args.output)

    size_mb = Path(args.output).stat().st_size / 1e6
    print(f"  Fichier: {size_mb:.1f} Mo")


if __name__ == "__main__":
    main()
