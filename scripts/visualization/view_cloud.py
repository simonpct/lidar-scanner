#!/usr/bin/env python3
"""
Visualisation rapide d'un nuage de points avec Open3D.

Usage:
    python view_cloud.py nuage.laz
    python view_cloud.py nuage.ply
"""

import sys
from pathlib import Path

import numpy as np
import open3d as o3d


def load_point_cloud(path: Path) -> o3d.geometry.PointCloud:
    """Charge un nuage de points depuis LAS/LAZ ou PLY."""
    suffix = path.suffix.lower()

    if suffix in (".las", ".laz"):
        import laspy

        las = laspy.read(str(path))
        points = np.vstack((las.x, las.y, las.z)).T

        pcd = o3d.geometry.PointCloud()
        pcd.points = o3d.utility.Vector3dVector(points)

        # Couleurs si disponibles
        try:
            colors = np.vstack((las.red, las.green, las.blue)).T
            # Normaliser (LAS stocke en 16-bit)
            if colors.max() > 255:
                colors = colors / 65535.0
            else:
                colors = colors / 255.0
            pcd.colors = o3d.utility.Vector3dVector(colors)
        except Exception:
            pass  # pas de couleurs

        return pcd

    elif suffix in (".ply", ".pcd"):
        return o3d.io.read_point_cloud(str(path))

    else:
        print(f"Format non supporté: {suffix}")
        sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print("Usage: python view_cloud.py <fichier.laz|.ply|.pcd>")
        sys.exit(1)

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"Fichier non trouvé: {path}")
        sys.exit(1)

    print(f"Chargement: {path}")
    pcd = load_point_cloud(path)
    print(f"  {len(pcd.points):,} points")

    if pcd.has_colors():
        print("  Couleurs: oui")
    else:
        print("  Couleurs: non (affichage en hauteur)")
        # Coloriser par hauteur (Z) si pas de couleurs
        points = np.asarray(pcd.points)
        z = points[:, 2]
        z_norm = (z - z.min()) / (z.max() - z.min() + 1e-10)
        import matplotlib.pyplot as plt

        cmap = plt.cm.viridis
        colors = cmap(z_norm)[:, :3]
        pcd.colors = o3d.utility.Vector3dVector(colors)

    o3d.visualization.draw_geometries(
        [pcd],
        window_name=f"Point Cloud - {path.name}",
        width=1400,
        height=900,
    )


if __name__ == "__main__":
    main()
