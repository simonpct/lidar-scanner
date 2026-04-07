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
import json
import os
import shutil
import signal
import subprocess
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse

app = FastAPI()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SCAN_DATA_DIR = Path(os.environ.get("SCAN_DATA_DIR", "/home/pi/scans"))
SCAN_SCRIPT = Path(__file__).parent.parent / "scripts" / "capture" / "scan_session.py"

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


# ---------------------------------------------------------------------------
# API — Status système
# ---------------------------------------------------------------------------
@app.get("/api/status")
async def get_status():
    storage = _get_storage()
    network = await _get_network()
    battery = _get_battery()
    scan = {
        "running": scan_state["running"],
        "paused": scan_state["paused"],
        "name": scan_state["name"],
        "started_at": scan_state["started_at"],
        "exit_code": scan_state["exit_code"],
        "stopped_at": scan_state["stopped_at"],
        "last_logs": scan_state["log_lines"][-30:],
    }
    sessions = _list_sessions()
    return {
        "storage": storage,
        "network": network,
        "battery": battery,
        "scan": scan,
        "sessions": sessions,
        "time": datetime.now().isoformat(),
    }


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


async def _get_network():
    """État réseau : eth0, wlan0, ap0."""
    eth0 = await _iface_status("eth0")
    wlan0 = await _iface_status("wlan0")
    ap0 = await _iface_status("ap0")

    # Vérifier le port série LiDAR + topic ROS2
    lidar_serial = Path("/dev/ttyUSB0").exists()
    lidar_topic = await _check_lidar_topic()

    # WiFi SSID connecté sur wlan0
    wifi_ssid = await _get_wifi_ssid("wlan0")

    return {
        "eth0": eth0,
        "wlan0": {**wlan0, "ssid": wifi_ssid},
        "ap0": ap0,
        "lidar_serial": lidar_serial,
        "lidar_topic": lidar_topic,
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
    # Essayer iwgetid d'abord, sinon nmcli
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
                # Format: "yes:MonSSID"
                for line in output.splitlines():
                    if line.startswith("yes:"):
                        return line.split(":", 1)[1]
                return None
            return output if output else None
        except FileNotFoundError:
            continue
    return None


async def _check_lidar_topic():
    """Vérifie si le topic LiDAR publie des données via ros2 topic hz."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "ros2", "topic", "hz", "/unitree_lidar/cloud", "--window", "3",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
            output = stdout.decode()
            # Output: "average rate: 10.00\n\tmin: ... max: ..."
            if "average rate" in output:
                for line in output.splitlines():
                    if "average rate" in line:
                        rate = line.split(":")[1].strip()
                        return {"active": True, "hz": rate}
            return {"active": False, "hz": None}
        except asyncio.TimeoutError:
            proc.kill()
            return {"active": False, "hz": None}
    except FileNotFoundError:
        return {"active": False, "hz": None, "error": "ros2 not found"}


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
            # Taille du dossier
            info["size_mb"] = round(_dir_size(d) / 1e6, 1)
            sessions.append(info)
    return sessions[:20]  # 20 plus récentes


# ---------------------------------------------------------------------------
# API — Contrôle scan
# ---------------------------------------------------------------------------
@app.post("/api/scan/start")
async def start_scan(request: Request):
    if scan_state["running"]:
        return {"error": "Un scan est déjà en cours", "name": scan_state["name"]}

    body = await request.json()
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
    )

    scan_state["running"] = True
    scan_state["process"] = proc
    scan_state["name"] = name
    scan_state["started_at"] = datetime.now().isoformat()
    scan_state["exit_code"] = None
    scan_state["stopped_at"] = None
    scan_state["log_lines"] = []

    # Lire la sortie en arrière-plan
    asyncio.get_event_loop().run_in_executor(None, _read_scan_output, proc)

    return {"status": "started", "name": name}


def _read_scan_output(proc):
    """Lit la sortie du process scan ligne par ligne."""
    try:
        for line in proc.stdout:
            scan_state["log_lines"].append(line.rstrip())
            # Garder les 200 dernières lignes
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

    scan_state["process"].send_signal(signal.SIGTSTP)
    scan_state["paused"] = True
    scan_state["log_lines"].append("[PAUSE]")
    return {"status": "paused", "name": scan_state["name"]}


@app.post("/api/scan/resume")
async def resume_scan():
    if not scan_state["running"] or not scan_state["process"]:
        return {"error": "Aucun scan en cours"}
    if not scan_state["paused"]:
        return {"error": "Scan pas en pause"}

    scan_state["process"].send_signal(signal.SIGCONT)
    scan_state["paused"] = False
    scan_state["log_lines"].append("[REPRISE]")
    return {"status": "resumed", "name": scan_state["name"]}


@app.post("/api/scan/stop")
async def stop_scan():
    if not scan_state["running"] or not scan_state["process"]:
        return {"error": "Aucun scan en cours"}

    proc = scan_state["process"]
    # Reprendre si en pause avant d'envoyer SIGINT
    if scan_state["paused"]:
        proc.send_signal(signal.SIGCONT)
        scan_state["paused"] = False
    proc.send_signal(signal.SIGINT)
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()

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
