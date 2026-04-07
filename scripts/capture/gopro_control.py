#!/usr/bin/env python3
"""
Contrôle de la GoPro Max depuis le Raspberry Pi 5 via WiFi.

La GoPro Max utilise l'ancienne API WiFi HTTP (pas Open GoPro).
Le RPi5 se connecte au WiFi AP de la GoPro (10.5.5.9).

Usage:
    # Mode interactif (lance le scan synchronisé LiDAR + GoPro)
    python gopro_control.py --mode scan --interval 2 --output data/raw/photos_360/

    # Juste prendre une photo
    python gopro_control.py --mode photo --output data/raw/photos_360/

    # Télécharger toutes les photos de la GoPro
    python gopro_control.py --mode download --output data/raw/photos_360/

Prérequis:
    1. Allumer la GoPro Max
    2. Connecter le RPi5 au WiFi de la GoPro :
       nmcli device wifi connect "GPxxxxxxxx" password "xxxxxxxx"
    3. pip install goprocam requests
"""

import argparse
import json
import os
import time
from datetime import datetime
from pathlib import Path

import requests

# API GoPro Max (legacy WiFi HTTP)
GOPRO_IP = "10.5.5.9"
GOPRO_BASE = f"http://{GOPRO_IP}"
GOPRO_MEDIA = f"{GOPRO_BASE}:8080/videos/DCIM"


def check_connection():
    """Vérifie la connexion à la GoPro."""
    try:
        r = requests.get(f"{GOPRO_BASE}/gp/gpControl/status", timeout=5)
        r.raise_for_status()
        print(f"GoPro connectée (status OK)")
        return True
    except requests.exceptions.RequestException as e:
        print(f"Erreur: impossible de contacter la GoPro à {GOPRO_IP}")
        print(f"  Vérifie que tu es connecté au WiFi de la GoPro.")
        print(f"  Détail: {e}")
        return False


def set_360_photo_mode():
    """Configure la GoPro en mode Photo 360."""
    # Mode Photo
    requests.get(f"{GOPRO_BASE}/gp/gpControl/command/mode?p=1", timeout=5)
    time.sleep(0.5)
    print("Mode: Photo 360")


def take_photo():
    """Déclenche une photo 360."""
    requests.get(f"{GOPRO_BASE}/gp/gpControl/command/shutter?p=1", timeout=5)
    timestamp = datetime.now().isoformat()
    print(f"  Photo prise à {timestamp}")
    # La GoPro Max met ~2s pour traiter une photo 360 (stitching interne)
    time.sleep(2.5)
    return timestamp


def get_media_list():
    """Récupère la liste des fichiers sur la GoPro."""
    r = requests.get(f"{GOPRO_BASE}/gp/gpMediaList", timeout=10)
    return r.json()


def get_last_file_info(media_list):
    """Retourne (folder, filename) du dernier fichier."""
    if not media_list.get("media"):
        return None, None
    last_folder = media_list["media"][-1]
    folder = last_folder["d"]
    last_file = last_folder["fs"][-1]["n"]
    return folder, last_file


def download_file(folder, filename, output_dir):
    """Télécharge un fichier depuis la GoPro."""
    url = f"{GOPRO_MEDIA}/{folder}/{filename}"
    local_path = output_dir / filename

    if local_path.exists():
        return local_path

    r = requests.get(url, stream=True, timeout=30)
    r.raise_for_status()

    with open(local_path, "wb") as f:
        for chunk in r.iter_content(chunk_size=65536):
            f.write(chunk)

    size_mb = local_path.stat().st_size / (1024 * 1024)
    print(f"  Téléchargé: {filename} ({size_mb:.1f} MB)")
    return local_path


def download_all(output_dir):
    """Télécharge tous les fichiers JPG de la GoPro."""
    media = get_media_list()
    count = 0

    for folder_info in media.get("media", []):
        folder = folder_info["d"]
        for file_info in folder_info.get("fs", []):
            filename = file_info["n"]
            if filename.lower().endswith(".jpg"):
                download_file(folder, filename, output_dir)
                count += 1

    print(f"\n{count} photos téléchargées dans {output_dir}")


def download_latest(output_dir):
    """Télécharge la dernière photo prise."""
    media = get_media_list()
    folder, filename = get_last_file_info(media)
    if folder and filename:
        return download_file(folder, filename, output_dir)
    return None


def scan_mode(output_dir, interval, duration=None):
    """
    Mode scan : prend des photos à intervalle régulier et les télécharge.

    Args:
        output_dir: dossier de sortie
        interval: secondes entre chaque photo
        duration: durée totale en secondes (None = infini, Ctrl+C pour arrêter)
    """
    set_360_photo_mode()

    # Log des captures (timestamps pour synchronisation avec LiDAR)
    log_path = output_dir / "capture_log.json"
    captures = []

    print(f"\nMode SCAN - photo toutes les {interval}s")
    print(f"  Sortie: {output_dir}")
    print(f"  Appuie sur Ctrl+C pour arrêter\n")

    start_time = time.time()
    count = 0

    try:
        while True:
            elapsed = time.time() - start_time
            if duration and elapsed >= duration:
                break

            print(f"[{count+1}] t={elapsed:.1f}s", end=" ")

            # Prendre la photo
            timestamp = take_photo()

            # Télécharger immédiatement
            local_path = download_latest(output_dir)

            # Logger la capture
            captures.append({
                "index": count,
                "timestamp_iso": timestamp,
                "timestamp_epoch": time.time(),
                "elapsed_seconds": elapsed,
                "filename": local_path.name if local_path else None,
            })

            # Sauvegarder le log au fur et à mesure
            with open(log_path, "w") as f:
                json.dump({"captures": captures}, f, indent=2)

            count += 1

            # Attendre l'intervalle (moins le temps de capture/download)
            remaining = interval - (time.time() - start_time - elapsed)
            if remaining > 0:
                time.sleep(remaining)

    except KeyboardInterrupt:
        print(f"\n\nScan arrêté. {count} photos capturées.")

    # Log final
    with open(log_path, "w") as f:
        json.dump({
            "total_captures": count,
            "interval_seconds": interval,
            "duration_seconds": time.time() - start_time,
            "captures": captures,
        }, f, indent=2)

    print(f"Log: {log_path}")


def main():
    parser = argparse.ArgumentParser(description="Contrôle GoPro Max via WiFi")
    parser.add_argument(
        "--mode",
        choices=["photo", "scan", "download", "status"],
        default="status",
        help="Mode: photo (1 photo), scan (continu), download (tout récupérer), status",
    )
    parser.add_argument("--output", default=".", help="Dossier de sortie")
    parser.add_argument(
        "--interval", type=float, default=2.0, help="Intervalle en secondes (mode scan)"
    )
    parser.add_argument(
        "--duration", type=float, default=None, help="Durée max en secondes (mode scan)"
    )

    args = parser.parse_args()
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    if not check_connection():
        return

    if args.mode == "status":
        r = requests.get(f"{GOPRO_BASE}/gp/gpControl/status", timeout=5)
        print(json.dumps(r.json(), indent=2))

    elif args.mode == "photo":
        set_360_photo_mode()
        take_photo()
        download_latest(output_dir)

    elif args.mode == "download":
        download_all(output_dir)

    elif args.mode == "scan":
        scan_mode(output_dir, args.interval, args.duration)


if __name__ == "__main__":
    main()
