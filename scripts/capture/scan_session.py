#!/usr/bin/env python3
"""
Orchestrateur de session de scan : LiDAR + GoPro Max synchronisés.

Lance en parallèle :
  1. L'enregistrement rosbag du LiDAR (via ros2 bag record)
  2. La capture photo 360 à intervalle régulier (via l'API WiFi GoPro)

Les timestamps sont enregistrés dans un log commun pour la synchronisation.

Usage (sur le RPi5):
    python scan_session.py \
        --name batiment_01 \
        --interval 2 \
        --data-dir /home/pi/scans/

Prérequis:
    - ROS2 lancé avec le driver Unitree L2
    - RPi5 connecté au WiFi de la GoPro Max
    - Ethernet connecté au Unitree L2
"""

import argparse
import json
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# Réutiliser les fonctions GoPro
sys.path.insert(0, str(Path(__file__).parent))
from gopro_control import (
    check_connection,
    download_latest,
    set_360_photo_mode,
    take_photo,
)


class ScanSession:
    def __init__(self, name, data_dir, interval, ros_topics, gopro_enabled=True):
        self.name = name
        self.data_dir = Path(data_dir) / name
        self.interval = interval
        self.ros_topics = ros_topics
        self.gopro_enabled = gopro_enabled

        # Créer les dossiers
        self.lidar_dir = self.data_dir / "lidar"
        self.lidar_dir.mkdir(parents=True, exist_ok=True)
        if self.gopro_enabled:
            self.photos_dir = self.data_dir / "photos_360"
            self.photos_dir.mkdir(parents=True, exist_ok=True)
        else:
            self.photos_dir = None

        self.rosbag_process = None
        self.running = False
        self.captures = []

    def start_rosbag(self):
        """Lance l'enregistrement rosbag en arrière-plan."""
        bag_path = self.lidar_dir / f"rosbag_{self.name}"
        cmd = [
            "ros2", "bag", "record",
            *self.ros_topics,
            "-o", str(bag_path),
        ]
        print(f"Démarrage rosbag: {' '.join(cmd)}")
        self.rosbag_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(1)
        if self.rosbag_process.poll() is not None:
            print("ERREUR: rosbag n'a pas démarré. ROS2 est-il lancé ?")
            return False
        print(f"  rosbag PID: {self.rosbag_process.pid}")
        return True

    def stop_rosbag(self):
        """Arrête proprement l'enregistrement rosbag."""
        if self.rosbag_process:
            self.rosbag_process.send_signal(signal.SIGINT)
            self.rosbag_process.wait(timeout=10)
            print("rosbag arrêté")

    def capture_loop(self):
        """Boucle de capture GoPro synchronisée (ou LiDAR seul)."""
        if self.gopro_enabled:
            set_360_photo_mode()

        start_time = time.time()
        count = 0

        print(f"\nSession '{self.name}' démarrée")
        if self.gopro_enabled:
            print(f"  Photos toutes les {self.interval}s")
        else:
            print(f"  Mode LiDAR uniquement (GoPro désactivée)")
        print(f"  Ctrl+C pour arrêter\n")

        try:
            while self.running:
                loop_start = time.time()
                elapsed = loop_start - start_time

                if self.gopro_enabled:
                    print(f"[{count+1}] t={elapsed:.1f}s", end=" ")

                    # Photo GoPro
                    timestamp_iso = take_photo()
                    timestamp_epoch = time.time()

                    # Télécharger
                    local_path = download_latest(self.photos_dir)

                    self.captures.append({
                        "index": count,
                        "timestamp_iso": timestamp_iso,
                        "timestamp_epoch": timestamp_epoch,
                        "elapsed_seconds": elapsed,
                        "filename": local_path.name if local_path else None,
                    })

                    count += 1

                    # Attendre pour respecter l'intervalle
                    spent = time.time() - loop_start
                    wait = max(0, self.interval - spent)
                    if wait > 0:
                        time.sleep(wait)
                else:
                    # LiDAR seul : juste attendre (rosbag tourne en arrière-plan)
                    if int(elapsed) % 10 == 0:
                        print(f"  LiDAR recording... t={elapsed:.0f}s", flush=True)
                    time.sleep(1)

        except KeyboardInterrupt:
            pass

        return count

    def save_session_log(self, duration, photo_count):
        """Sauvegarde le log de session complet."""
        log = {
            "session_name": self.name,
            "start_time": self.captures[0]["timestamp_iso"] if self.captures else None,
            "duration_seconds": duration,
            "photo_count": photo_count,
            "photo_interval_seconds": self.interval,
            "ros_topics": self.ros_topics,
            "lidar_dir": str(self.lidar_dir),
            "photos_dir": str(self.photos_dir),
            "captures": self.captures,
        }

        log_path = self.data_dir / "session_log.json"
        with open(log_path, "w") as f:
            json.dump(log, f, indent=2)

        print(f"Log de session: {log_path}")

    def run(self):
        """Lance la session complète."""
        print(f"=== Session de scan: {self.name} ===\n")

        # 1. Vérifier la GoPro (si activée)
        if self.gopro_enabled and not check_connection():
            return

        # 2. Lancer le rosbag
        if not self.start_rosbag():
            return

        # 3. Boucle de capture
        self.running = True
        start = time.time()

        def handle_sigint(sig, frame):
            self.running = False

        signal.signal(signal.SIGINT, handle_sigint)

        photo_count = self.capture_loop()
        duration = time.time() - start

        # 4. Arrêter
        print(f"\n\nArrêt de la session...")
        self.stop_rosbag()
        self.save_session_log(duration, photo_count)

        print(f"\n=== Session terminée ===")
        print(f"  Durée: {duration:.0f}s")
        print(f"  Photos: {photo_count}")
        print(f"  Données: {self.data_dir}")


def main():
    parser = argparse.ArgumentParser(description="Session de scan LiDAR + GoPro")
    parser.add_argument("--name", required=True, help="Nom de la session")
    parser.add_argument(
        "--data-dir", default=".", help="Dossier racine des données"
    )
    parser.add_argument(
        "--interval", type=float, default=2.0, help="Intervalle photo (secondes)"
    )
    parser.add_argument(
        "--topics",
        nargs="+",
        default=["/unitree_lidar/cloud", "/unitree_lidar/imu"],
        help="Topics ROS2 à enregistrer",
    )
    parser.add_argument(
        "--no-gopro",
        action="store_true",
        help="Scan LiDAR uniquement, sans photos GoPro",
    )

    args = parser.parse_args()

    session = ScanSession(
        name=args.name,
        data_dir=args.data_dir,
        interval=args.interval,
        ros_topics=args.topics,
        gopro_enabled=not args.no_gopro,
    )
    session.run()


if __name__ == "__main__":
    main()
