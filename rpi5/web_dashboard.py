#!/usr/bin/env python3
"""
Dashboard web pour le Raspberry Pi 5 — LiDAR Scanner.

Affiche l'état du système (stockage, réseau, batterie) et permet
de lancer/arrêter des sessions de scan depuis un téléphone.

Démarrage :
    python web_dashboard.py                  # port 8080
    python web_dashboard.py --port 80        # port 80 (avec sudo)

Accès :
    http://192.168.4.1:8080  (via hotspot ap0 "LidarScanner")
"""

import asyncio
import io
import json
import os
import shutil
import signal
import subprocess
import time
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, Response

app = FastAPI()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SCAN_DATA_DIR = Path(os.environ.get("SCAN_DATA_DIR", "/home/simon/scans"))
SCAN_SCRIPT = Path(__file__).parent.parent / "scripts" / "capture" / "scan_session.py"
LIDAR_MODE_BIN = "/usr/local/bin/lidar_mode"

# État global du scan en cours
scan_state = {
    "running": False,
    "paused": False,
    "process": None,
    "name": None,
    "started_at": None,
    "log_lines": [],
    "exit_code": None,
    "stopped_at": None,
}

# Cache réseau (refreshed en arrière-plan toutes les 5s)
_network_cache = {
    "data": None,
    "updated_at": 0,
}
_NETWORK_CACHE_TTL = 5  # secondes


# ---------------------------------------------------------------------------
# API — Status système (rapide, données cachées pour le réseau)
# ---------------------------------------------------------------------------
@app.get("/api/status")
async def get_status():
    # Données rapides (instantanées)
    storage = _get_storage()
    battery = _get_battery()
    cpu_temp = _get_cpu_temp()
    scan = {
        "running": scan_state["running"],
        "paused": scan_state["paused"],
        "name": scan_state["name"],
        "started_at": scan_state["started_at"],
        "exit_code": scan_state["exit_code"],
        "stopped_at": scan_state["stopped_at"],
        "last_logs": scan_state["log_lines"][-30:],
    }

    # Données lentes (cachées, refresh en arrière-plan)
    now = time.monotonic()
    if _network_cache["data"] is None or now - _network_cache["updated_at"] > _NETWORK_CACHE_TTL:
        # Premier appel : lancer le refresh et retourner des données vides
        asyncio.ensure_future(_refresh_network_cache())
    network = _network_cache["data"] or {
        "eth0": {"exists": False, "up": False, "ip": None},
        "wlan0": {"exists": False, "up": False, "ip": None, "ssid": None},
        "ap0": {"exists": False, "up": False, "ip": None},
        "lidar_connected": False,
        "lidar_topic": {"active": False, "publishers": 0},
    }

    sessions = _list_sessions()
    return {
        "storage": storage,
        "network": network,
        "battery": battery,
        "cpu_temp": cpu_temp,
        "scan": scan,
        "sessions": sessions,
        "time": datetime.now().isoformat(),
    }


async def _refresh_network_cache():
    """Refresh le cache réseau en arrière-plan."""
    try:
        data = await _get_network()
        _network_cache["data"] = data
        _network_cache["updated_at"] = time.monotonic()
    except Exception:
        pass


def _get_storage():
    """Espace disque sur la partition principale et le dossier scans."""
    usage = shutil.disk_usage("/")
    scans_size = _dir_size(SCAN_DATA_DIR) if SCAN_DATA_DIR.exists() else 0
    return {
        "total_gb": round(usage.total / 1e9, 1),
        "used_gb": round(usage.used / 1e9, 1),
        "free_gb": round(usage.free / 1e9, 1),
        "percent": round(usage.used / usage.total * 100, 1),
        "scans_gb": round(scans_size / 1e9, 2),
    }


def _dir_size(path: Path) -> int:
    total = 0
    try:
        for f in path.rglob("*"):
            if f.is_file():
                total += f.stat().st_size
    except PermissionError:
        pass
    return total


def _get_battery():
    """Lit la batterie via sysfs (UPS HAT) ou retourne None."""
    power_supply = Path("/sys/class/power_supply")
    if not power_supply.exists():
        return None

    for ps in power_supply.iterdir():
        type_file = ps / "type"
        if type_file.exists() and type_file.read_text().strip() == "Battery":
            capacity = ps / "capacity"
            status = ps / "status"
            return {
                "percent": int(capacity.read_text().strip()) if capacity.exists() else None,
                "status": status.read_text().strip() if status.exists() else None,
            }
    return None


def _get_cpu_temp():
    """Température CPU via sysfs."""
    temp_file = Path("/sys/class/thermal/thermal_zone0/temp")
    if temp_file.exists():
        try:
            millideg = int(temp_file.read_text().strip())
            return round(millideg / 1000, 1)
        except (ValueError, PermissionError):
            pass
    return None


async def _get_network():
    """État réseau : LiDAR (Ethernet), wlan0, ap0."""
    # Lancer les checks en parallèle
    wlan0, ap0, eth0, lidar_topic, slam_topic, wifi_ssid = await asyncio.gather(
        _iface_status("wlan0"),
        _iface_status("ap0"),
        _iface_status("eth0"),
        _check_ros2_topic("/unilidar/cloud"),
        _check_ros2_topic("/odometry"),
        _get_wifi_ssid("wlan0"),
    )

    lidar_connected = eth0["up"] and eth0["ip"] is not None

    return {
        "eth0": eth0,
        "wlan0": {**wlan0, "ssid": wifi_ssid},
        "ap0": ap0,
        "lidar_connected": lidar_connected,
        "lidar_topic": lidar_topic,
        "slam_topic": slam_topic,
    }


async def _iface_status(iface: str):
    """Vérifie si une interface réseau est UP et son IP."""
    operstate = Path(f"/sys/class/net/{iface}/operstate")
    if not operstate.exists():
        return {"exists": False, "up": False, "ip": None}

    up = operstate.read_text().strip() == "up"

    ip = None
    if up:
        proc = await asyncio.create_subprocess_exec(
            "ip", "-4", "-j", "addr", "show", iface,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        try:
            data = json.loads(stdout)
            if data and data[0].get("addr_info"):
                ip = data[0]["addr_info"][0]["local"]
        except (json.JSONDecodeError, IndexError, KeyError):
            pass

    return {"exists": True, "up": up, "ip": ip}


async def _get_wifi_ssid(iface: str):
    for cmd in [
        ["iwgetid", iface, "--raw"],
        ["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"],
    ]:
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            stdout, _ = await proc.communicate()
            if proc.returncode != 0:
                continue
            output = stdout.decode().strip()
            if "nmcli" in cmd[0]:
                for line in output.splitlines():
                    if line.startswith("yes:"):
                        return line.split(":", 1)[1]
                return None
            return output if output else None
        except FileNotFoundError:
            continue
    return None


async def _check_ros2_topic(topic: str):
    """Vérifie si un topic ROS2 a des publishers via ros2 topic info."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "ros2", "topic", "info", topic,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=3)
            output = stdout.decode()
            if "Publisher count:" in output:
                for line in output.splitlines():
                    if "Publisher count:" in line:
                        count = int(line.split(":")[1].strip())
                        if count > 0:
                            return {"active": True, "publishers": count}
            return {"active": False, "publishers": 0}
        except asyncio.TimeoutError:
            proc.kill()
            return {"active": False, "publishers": 0}
    except FileNotFoundError:
        return {"active": False, "publishers": 0, "error": "ros2 not found"}


def _list_sessions():
    """Liste les sessions de scan existantes."""
    if not SCAN_DATA_DIR.exists():
        return []
    sessions = []
    for d in sorted(SCAN_DATA_DIR.iterdir(), reverse=True):
        if d.is_dir():
            log = d / "session_log.json"
            info = {"name": d.name, "path": str(d)}
            if log.exists():
                try:
                    data = json.loads(log.read_text())
                    info["photos"] = data.get("photo_count", 0)
                    info["duration"] = data.get("duration_seconds", 0)
                except (json.JSONDecodeError, KeyError):
                    pass
            info["size_mb"] = round(_dir_size(d) / 1e6, 1)
            lidar_dir = d / "lidar"
            info["lidar_mb"] = round(_dir_size(lidar_dir) / 1e6, 1) if lidar_dir.exists() else 0
            info["empty"] = info["size_mb"] < 0.1
            sessions.append(info)
    return sessions[:20]


@app.delete("/api/sessions/{name}")
async def delete_session(name: str):
    """Supprime une session."""
    import shutil as _shutil
    session_dir = SCAN_DATA_DIR / name
    if not session_dir.exists():
        return {"error": "Session introuvable"}
    if not session_dir.is_dir():
        return {"error": "Pas un dossier"}
    if SCAN_DATA_DIR not in session_dir.parents:
        return {"error": "Chemin invalide"}
    _shutil.rmtree(session_dir)
    return {"ok": True, "deleted": name}


# ---------------------------------------------------------------------------
# API — Snapshot point cloud (vue du dessus, PNG)
# ---------------------------------------------------------------------------
@app.get("/api/snapshot")
async def snapshot():
    """Génère une vue bird's eye du point cloud actuel (live) en PNG."""
    loop = asyncio.get_event_loop()
    try:
        img_bytes = await asyncio.wait_for(
            loop.run_in_executor(None, _generate_snapshot_live),
            timeout=20,
        )
        if img_bytes:
            return Response(content=img_bytes, media_type="image/png")
        return {"error": "Pas de données point cloud"}
    except asyncio.TimeoutError:
        return {"error": "Timeout génération snapshot"}
    except Exception as e:
        return {"error": str(e)}


@app.get("/api/sessions/{name}/snapshot")
async def session_snapshot(name: str):
    """Génère une vue bird's eye du point cloud d'une session existante."""
    session_dir = SCAN_DATA_DIR / name
    if not session_dir.exists():
        return {"error": "Session introuvable"}

    # Trouver le rosbag
    lidar_dir = session_dir / "lidar"
    if not lidar_dir.exists():
        return {"error": "Pas de données LiDAR"}

    # Chercher le dossier rosbag (contient metadata.yaml)
    bag_path = None
    for d in lidar_dir.iterdir():
        if d.is_dir() and (d / "metadata.yaml").exists():
            bag_path = d
            break

    if not bag_path:
        return {"error": "Rosbag introuvable"}

    # Vérifier si un snapshot caché existe déjà
    cache_path = session_dir / "snapshot.png"
    if cache_path.exists():
        return Response(content=cache_path.read_bytes(), media_type="image/png")

    loop = asyncio.get_event_loop()
    try:
        img_bytes = await asyncio.wait_for(
            loop.run_in_executor(None, _generate_snapshot_from_bag, str(bag_path)),
            timeout=30,
        )
        if img_bytes:
            # Cacher le résultat
            cache_path.write_bytes(img_bytes)
            return Response(content=img_bytes, media_type="image/png")
        return {"error": "Pas de points dans le rosbag"}
    except asyncio.TimeoutError:
        return {"error": "Timeout lecture rosbag"}
    except Exception as e:
        return {"error": str(e)}


def _generate_snapshot_live():
    """Capture un snapshot live via le rosbag en cours ou un enregistrement temporaire."""
    import struct

    # Si un scan est en cours, lire son rosbag
    if scan_state["running"] and scan_state["name"]:
        session_dir = SCAN_DATA_DIR / scan_state["name"] / "lidar"
        if session_dir.exists():
            for d in session_dir.iterdir():
                if d.is_dir() and (d / "metadata.yaml").exists():
                    return _generate_snapshot_from_bag(str(d))

    # Sinon, faire un enregistrement temporaire de 2 secondes
    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        bag_path = os.path.join(tmpdir, "snap")
        try:
            subprocess.run(
                ["ros2", "bag", "record", "/unilidar/cloud",
                 "-o", bag_path, "--max-duration", "2"],
                capture_output=True, timeout=10,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return None

        # Le bag est dans snap/
        actual_bag = os.path.join(tmpdir, "snap")
        if os.path.isdir(actual_bag) and os.path.exists(os.path.join(actual_bag, "metadata.yaml")):
            return _generate_snapshot_from_bag(actual_bag)

    return None


def _generate_snapshot_from_bag(bag_path: str):
    """Lit un rosbag et génère un PNG bird's eye avec tous les points accumulés."""
    import struct

    try:
        from rosbag2_py import SequentialReader, StorageOptions, ConverterOptions
        from rclpy.serialization import deserialize_message
        from sensor_msgs.msg import PointCloud2
    except ImportError:
        # Fallback : utiliser ros2 bag play + echo (plus lent)
        return _snapshot_from_bag_cli(bag_path)

    reader = SequentialReader()
    storage_options = StorageOptions(uri=bag_path, storage_id="")
    converter_options = ConverterOptions(
        input_serialization_format="cdr",
        output_serialization_format="cdr",
    )
    reader.open(storage_options, converter_options)

    all_x = []
    all_y = []
    max_points = 500_000  # Limiter pour perf

    while reader.has_next() and len(all_x) < max_points:
        topic, data, _ = reader.read_next()
        if topic != "/unilidar/cloud":
            continue

        msg = deserialize_message(data, PointCloud2)
        raw = bytes(msg.data)
        ps = msg.point_step
        n = msg.width * max(msg.height, 1)

        for i in range(min(n, (max_points - len(all_x)))):
            offset = i * ps
            if offset + 8 > len(raw):
                break
            x = struct.unpack_from("<f", raw, offset)[0]
            y = struct.unpack_from("<f", raw, offset + 4)[0]
            if abs(x) < 200 and abs(y) < 200 and (x != 0 or y != 0):
                all_x.append(x)
                all_y.append(y)

    if len(all_x) < 10:
        return None

    return _render_birdseye(all_x, all_y, img_size=600)


def _snapshot_from_bag_cli(bag_path: str):
    """Fallback : lit un rosbag via ros2 bag play + topic echo (lent)."""
    # Pas idéal mais fonctionne sans imports ROS2 Python
    try:
        # Jouer le bag et capturer le premier message
        play = subprocess.Popen(
            ["ros2", "bag", "play", bag_path, "--rate", "100"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        result = subprocess.run(
            ["ros2", "topic", "echo", "/unilidar/cloud", "--once"],
            capture_output=True, text=True, timeout=10,
        )
        play.terminate()
        play.wait(timeout=5)

        if result.returncode != 0 or not result.stdout:
            return None
        return _snapshot_from_ros2_echo(result.stdout)
    except Exception:
        return None


def _snapshot_from_ros2_echo(yaml_text: str):
    """Parse la sortie YAML de ros2 topic echo pour PointCloud2 et génère un PNG."""
    try:
        import struct

        # Extraire les données binaires du champ 'data'
        lines = yaml_text.split("\n")
        width = height = 0
        point_step = 0
        data_line_start = -1

        for i, line in enumerate(lines):
            if line.startswith("width:"):
                width = int(line.split(":")[1].strip())
            elif line.startswith("height:"):
                height = int(line.split(":")[1].strip())
            elif line.startswith("point_step:"):
                point_step = int(line.split(":")[1].strip())
            elif line.startswith("data:"):
                data_line_start = i
                break

        if width == 0 or point_step == 0 or data_line_start < 0:
            return None

        num_points = width * max(height, 1)

        # Extraire les bytes du champ data (format: [b1, b2, b3, ...])
        data_text = ""
        for line in lines[data_line_start:]:
            data_text += line
        # Trouver le contenu entre [ et ]
        start = data_text.index("[")
        end = data_text.index("]")
        byte_strs = data_text[start + 1:end].split(",")
        raw_bytes = bytes([int(b.strip()) for b in byte_strs if b.strip()])

        # Extraire x, y (floats, offset 0 et 4 typiquement)
        points_x = []
        points_y = []
        for i in range(min(num_points, len(raw_bytes) // point_step)):
            offset = i * point_step
            x = struct.unpack_from("<f", raw_bytes, offset)[0]
            y = struct.unpack_from("<f", raw_bytes, offset + 4)[0]
            # Filtrer les points invalides
            if abs(x) < 100 and abs(y) < 100 and (x != 0 or y != 0):
                points_x.append(x)
                points_y.append(y)

        if len(points_x) < 10:
            return None

        # Générer le PNG bird's eye view
        return _render_birdseye(points_x, points_y)

    except Exception:
        return None


def _render_birdseye(points_x: list, points_y: list, img_size: int = 400) -> bytes:
    """Rend une image PNG bird's eye view à partir de coordonnées x, y."""
    # Créer une image en mémoire (sans dépendance externe lourde)
    # Format: PGM simple converti en PNG via zlib
    import zlib

    margin = 0.1
    min_x, max_x = min(points_x), max(points_x)
    min_y, max_y = min(points_y), max(points_y)
    range_x = max_x - min_x or 1
    range_y = max_y - min_y or 1
    # Garder l'aspect ratio
    max_range = max(range_x, range_y) * (1 + 2 * margin)
    cx = (min_x + max_x) / 2
    cy = (min_y + max_y) / 2

    # Créer le buffer image (RGBA)
    pixels = bytearray(img_size * img_size * 4)
    # Fond sombre
    for i in range(img_size * img_size):
        pixels[i * 4] = 15      # R
        pixels[i * 4 + 1] = 17  # G
        pixels[i * 4 + 2] = 23  # B
        pixels[i * 4 + 3] = 255 # A

    # Dessiner les points
    for x, y in zip(points_x, points_y):
        px = int((x - cx + max_range / 2) / max_range * (img_size - 1))
        py = int((y - cy + max_range / 2) / max_range * (img_size - 1))
        py = img_size - 1 - py  # Inverser Y
        if 0 <= px < img_size and 0 <= py < img_size:
            idx = (py * img_size + px) * 4
            pixels[idx] = 34       # R (vert du thème)
            pixels[idx + 1] = 197  # G
            pixels[idx + 2] = 94   # B
            pixels[idx + 3] = 255  # A

    # Encoder en PNG manuellement (pas besoin de Pillow)
    def _png_chunk(chunk_type, data):
        c = chunk_type + data
        crc = zlib.crc32(c) & 0xFFFFFFFF
        return len(data).to_bytes(4, "big") + c + crc.to_bytes(4, "big")

    # IHDR
    ihdr = (
        img_size.to_bytes(4, "big") +
        img_size.to_bytes(4, "big") +
        b'\x08'  # bit depth 8
        b'\x06'  # color type RGBA
        b'\x00'  # compression
        b'\x00'  # filter
        b'\x00'  # interlace
    )

    # IDAT — raw image data with filter bytes
    raw_data = bytearray()
    for row in range(img_size):
        raw_data.append(0)  # filter: none
        start = row * img_size * 4
        raw_data.extend(pixels[start:start + img_size * 4])

    compressed = zlib.compress(bytes(raw_data))

    # Assemble PNG
    png = b'\x89PNG\r\n\x1a\n'
    png += _png_chunk(b'IHDR', ihdr)
    png += _png_chunk(b'IDAT', compressed)
    png += _png_chunk(b'IEND', b'')

    return png


# ---------------------------------------------------------------------------
# API — Contrôle scan
# ---------------------------------------------------------------------------
async def _systemctl(action: str, service: str):
    """Lance systemctl start/stop/restart sur un service."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "sudo", "systemctl", action, service,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await asyncio.wait_for(proc.communicate(), timeout=10)
        return proc.returncode == 0
    except Exception:
        return False


async def _set_lidar_mode(mode: str):
    """Appelle lidar_mode pour démarrer ou arrêter la rotation du LiDAR."""
    if not Path(LIDAR_MODE_BIN).exists():
        return False, "lidar_mode non installé"
    try:
        proc = await asyncio.create_subprocess_exec(
            LIDAR_MODE_BIN, mode,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=5)
        if proc.returncode == 0:
            return True, stdout.decode().strip()
        return False, stderr.decode().strip()
    except asyncio.TimeoutError:
        return False, "timeout"
    except Exception as e:
        return False, str(e)


@app.post("/api/lidar/{command}")
async def lidar_control(command: str):
    """Contrôle direct du LiDAR : start, stop, reset, sync."""
    if command not in ("start", "stop", "reset", "sync"):
        return {"error": f"Commande inconnue: {command}"}
    ok, msg = await _set_lidar_mode(command)
    return {"ok": ok, "message": msg}


@app.post("/api/scan/start")
async def start_scan(request: Request):
    if scan_state["running"]:
        return {"error": "Un scan est déjà en cours", "name": scan_state["name"]}

    # Réveiller le LiDAR
    ok, msg = await _set_lidar_mode("start")
    if not ok:
        scan_state["log_lines"].append(f"[WARN] lidar_mode start: {msg}")

    body = await request.json()

    # Démarrer le SLAM si demandé
    if body.get("slam", True):
        await _systemctl("start", "lidar-slam")
    name = body.get("name", f"scan_{datetime.now():%Y%m%d_%H%M%S}")
    interval = body.get("interval", 2.0)
    gopro = body.get("gopro", True)
    data_dir = str(SCAN_DATA_DIR)

    cmd = [
        "python3", str(SCAN_SCRIPT),
        "--name", name,
        "--interval", str(interval),
        "--data-dir", data_dir,
    ]
    if not gopro:
        cmd.append("--no-gopro")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        preexec_fn=os.setsid,
    )

    scan_state["running"] = True
    scan_state["process"] = proc
    scan_state["name"] = name
    scan_state["started_at"] = datetime.now().isoformat()
    scan_state["exit_code"] = None
    scan_state["stopped_at"] = None
    scan_state["log_lines"] = []

    asyncio.get_event_loop().run_in_executor(None, _read_scan_output, proc)

    return {"status": "started", "name": name}


def _read_scan_output(proc):
    """Lit la sortie du process scan ligne par ligne."""
    try:
        for line in proc.stdout:
            scan_state["log_lines"].append(line.rstrip())
            if len(scan_state["log_lines"]) > 200:
                scan_state["log_lines"] = scan_state["log_lines"][-200:]
    except Exception as e:
        scan_state["log_lines"].append(f"[ERREUR LECTURE] {e}")
    finally:
        exit_code = proc.wait()
        scan_state["exit_code"] = exit_code
        scan_state["stopped_at"] = datetime.now().isoformat()
        scan_state["running"] = False
        scan_state["paused"] = False
        scan_state["process"] = None
        if exit_code != 0:
            scan_state["log_lines"].append(f"[TERMINÉ] code de sortie: {exit_code}")


@app.post("/api/scan/pause")
async def pause_scan():
    if not scan_state["running"] or not scan_state["process"]:
        return {"error": "Aucun scan en cours"}
    if scan_state["paused"]:
        return {"error": "Scan déjà en pause"}

    os.killpg(os.getpgid(scan_state["process"].pid), signal.SIGTSTP)
    scan_state["paused"] = True
    scan_state["log_lines"].append("[PAUSE]")
    return {"status": "paused", "name": scan_state["name"]}


@app.post("/api/scan/resume")
async def resume_scan():
    if not scan_state["running"] or not scan_state["process"]:
        return {"error": "Aucun scan en cours"}
    if not scan_state["paused"]:
        return {"error": "Scan pas en pause"}

    os.killpg(os.getpgid(scan_state["process"].pid), signal.SIGCONT)
    scan_state["paused"] = False
    scan_state["log_lines"].append("[REPRISE]")
    return {"status": "resumed", "name": scan_state["name"]}


@app.post("/api/scan/stop")
async def stop_scan():
    if not scan_state["running"] or not scan_state["process"]:
        return {"error": "Aucun scan en cours"}

    proc = scan_state["process"]
    if scan_state["paused"]:
        os.killpg(os.getpgid(proc.pid), signal.SIGCONT)
        scan_state["paused"] = False
    os.killpg(os.getpgid(proc.pid), signal.SIGINT)
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)

    ok, msg = await _set_lidar_mode("stop")
    if not ok:
        scan_state["log_lines"].append(f"[WARN] lidar_mode stop: {msg}")

    # Arrêter le SLAM
    await _systemctl("stop", "lidar-slam")

    return {"status": "stopped", "name": scan_state["name"]}


@app.get("/api/scan/logs")
async def scan_logs():
    return {"lines": scan_state["log_lines"][-50:]}


# ---------------------------------------------------------------------------
# Page HTML
# ---------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
async def index():
    html_path = Path(__file__).parent / "static" / "index.html"
    return html_path.read_text()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import argparse

    import uvicorn

    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()

    print(f"Dashboard: http://{args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port)
