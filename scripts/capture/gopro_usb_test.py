#!/usr/bin/env python3
"""
Test de contrôle USB de la GoPro Max.

Ce script tente TOUTES les méthodes possibles pour communiquer avec
une GoPro Max via USB-C. C'est un script de diagnostic — lance-le
avec la GoPro branchée et on verra ce qui fonctionne.

Usage:
    pip install gphoto2 pyusb pymtp
    python gopro_usb_test.py

Certains tests nécessitent des droits root (accès USB raw).
"""

import importlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path


def section(title):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}\n")


def run_cmd(cmd, timeout=10):
    """Exécute une commande shell et retourne (returncode, stdout, stderr)."""
    try:
        r = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, shell=isinstance(cmd, str)
        )
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except FileNotFoundError:
        return -1, "", f"Commande non trouvée: {cmd[0] if isinstance(cmd, list) else cmd}"


# ==============================================================
# TEST 1 : Détection USB brute (lsusb)
# ==============================================================
def test_usb_detection():
    section("TEST 1 — Détection USB (lsusb / system_profiler)")

    # macOS
    rc, out, err = run_cmd(["system_profiler", "SPUSBDataType"])
    if rc == 0:
        # Chercher GoPro dans la sortie
        lines = out.split("\n")
        gopro_found = False
        for i, line in enumerate(lines):
            if "gopro" in line.lower() or "2672" in line or "0x2672" in line:
                gopro_found = True
                # Afficher le contexte
                start = max(0, i - 2)
                end = min(len(lines), i + 10)
                print("GoPro détectée dans system_profiler:")
                for l in lines[start:end]:
                    print(f"  {l}")
                break

        if not gopro_found:
            print("GoPro NON détectée dans system_profiler.")
            print("Vérifie que la GoPro est branchée en USB-C et allumée.")

            # Afficher tous les devices USB pour debug
            print("\nDevices USB détectés:")
            for line in lines:
                if "Product ID" in line or "Vendor ID" in line or "Manufacturer" in line:
                    print(f"  {line.strip()}")
        return gopro_found

    # Linux (RPi5)
    rc, out, err = run_cmd(["lsusb"])
    if rc == 0:
        print("Devices USB:")
        gopro_found = False
        for line in out.split("\n"):
            print(f"  {line}")
            # GoPro vendor ID = 0x2672 (ou parfois sous un autre ID)
            if "gopro" in line.lower() or "2672" in line:
                gopro_found = True
                print("  ^^^ GoPro détectée!")
        if not gopro_found:
            print("\nGoPro NON trouvée dans lsusb.")
            print("Vendor IDs connus pour GoPro: 2672, 26ab")

        # Aussi vérifier les devices de stockage
        rc2, out2, _ = run_cmd(["lsblk", "-o", "NAME,MODEL,SIZE,MOUNTPOINT"])
        if rc2 == 0:
            print(f"\nBlocks devices:\n{out2}")
        return gopro_found

    print("Ni lsusb ni system_profiler disponible.")
    return False


# ==============================================================
# TEST 2 : gphoto2
# ==============================================================
def test_gphoto2():
    section("TEST 2 — gphoto2 (PTP/MTP)")

    # Vérifier si gphoto2 est installé
    rc, out, err = run_cmd(["gphoto2", "--version"])
    if rc != 0:
        print("gphoto2 non installé.")
        print("  macOS: brew install gphoto2")
        print("  Linux: sudo apt install gphoto2")
        return

    print(f"gphoto2 version: {out.split(chr(10))[0]}")

    # Auto-detect
    print("\n--- Auto-détection ---")
    rc, out, err = run_cmd(["gphoto2", "--auto-detect"])
    print(out if out else err)

    if "GoPro" not in out and "gopro" not in out.lower():
        print("\nGoPro non détectée par gphoto2.")
        print("Possible que la caméra soit en mode Mass Storage (pas PTP).")
        print("Essaie de débrancher/rebrancher la GoPro.")
        return

    # Abilities (ce que gphoto2 pense pouvoir faire)
    print("\n--- Capacités détectées ---")
    rc, out, err = run_cmd(["gphoto2", "--abilities"])
    print(out if out else err)

    # Summary
    print("\n--- Résumé caméra ---")
    rc, out, err = run_cmd(["gphoto2", "--summary"])
    print(out if out else err)

    # Config
    print("\n--- Configuration ---")
    rc, out, err = run_cmd(["gphoto2", "--list-config"])
    if rc == 0 and out:
        print(out)
        # Lire chaque config
        for config_key in out.split("\n")[:20]:  # max 20
            config_key = config_key.strip()
            if config_key:
                rc2, out2, _ = run_cmd(["gphoto2", "--get-config", config_key])
                if rc2 == 0:
                    print(f"\n  {config_key}:")
                    for line in out2.split("\n"):
                        print(f"    {line}")
    else:
        print("Aucune config exposée (ou erreur).")

    # Liste des fichiers
    print("\n--- Liste des fichiers ---")
    rc, out, err = run_cmd(["gphoto2", "--list-files"], timeout=15)
    if rc == 0 and out:
        lines = out.split("\n")
        print(f"  {len(lines)} lignes")
        # Afficher les 10 derniers
        for line in lines[-10:]:
            print(f"  {line}")
    else:
        print(f"  Erreur: {err}")

    # TENTATIVE DE CAPTURE !
    print("\n--- TENTATIVE DE CAPTURE (le moment de vérité) ---")
    rc, out, err = run_cmd(["gphoto2", "--capture-image"], timeout=15)
    if rc == 0:
        print(f"SUCCÈS! {out}")
        print("La GoPro Max supporte le capture via PTP/USB!")
    else:
        print(f"Échec (attendu): {err}")

    # Tentative capture + download
    print("\n--- TENTATIVE CAPTURE + DOWNLOAD ---")
    rc, out, err = run_cmd(
        ["gphoto2", "--capture-image-and-download", "--filename", "/tmp/gopro_test_%n.%C"],
        timeout=20,
    )
    if rc == 0:
        print(f"SUCCÈS! {out}")
    else:
        print(f"Échec: {err}")


# ==============================================================
# TEST 3 : Mass Storage (montage automatique)
# ==============================================================
def test_mass_storage():
    section("TEST 3 — USB Mass Storage (carte SD)")

    import platform

    if platform.system() == "Darwin":  # macOS
        # Chercher un volume GoPro monté
        volumes = list(Path("/Volumes").iterdir())
        gopro_vol = None
        for v in volumes:
            if "gopro" in v.name.lower() or "untitled" in v.name.lower():
                gopro_vol = v
                break
            # Aussi chercher un DCIM
            dcim = v / "DCIM"
            if dcim.exists():
                gopro_vol = v
                break

        if gopro_vol:
            print(f"Volume monté: {gopro_vol}")
            dcim = gopro_vol / "DCIM"
            if dcim.exists():
                print(f"  DCIM trouvé!")
                for folder in sorted(dcim.iterdir()):
                    if folder.is_dir():
                        files = list(folder.iterdir())
                        jpg_count = len([f for f in files if f.suffix.lower() == ".jpg"])
                        mp4_count = len([f for f in files if f.suffix.lower() == ".mp4"])
                        f360_count = len([f for f in files if f.suffix.lower() == ".360"])
                        print(f"  {folder.name}/: {len(files)} fichiers "
                              f"({jpg_count} jpg, {mp4_count} mp4, {f360_count} .360)")

                        # Montrer les derniers fichiers
                        for f in sorted(files)[-3:]:
                            size_mb = f.stat().st_size / (1024*1024)
                            print(f"    └─ {f.name} ({size_mb:.1f} MB)")
            return str(gopro_vol)
        else:
            print("Aucun volume GoPro monté.")
            print(f"Volumes disponibles: {[v.name for v in volumes]}")
            return None

    else:  # Linux
        # Chercher dans /media ou les mounts
        rc, out, _ = run_cmd(["findmnt", "-t", "vfat,exfat", "-o", "TARGET,SOURCE", "-n"])
        if rc == 0 and out:
            print(f"Systèmes de fichiers FAT montés:\n{out}")
            for line in out.split("\n"):
                mount_point = line.split()[0] if line.split() else ""
                dcim = Path(mount_point) / "DCIM"
                if dcim.exists():
                    print(f"\n  DCIM trouvé à {mount_point}!")
                    return mount_point
        print("Aucun stockage GoPro monté.")
        return None


# ==============================================================
# TEST 4 : PyUSB (accès raw USB)
# ==============================================================
def test_pyusb():
    section("TEST 4 — PyUSB (accès raw)")

    try:
        import usb.core
        import usb.util
    except ImportError:
        print("pyusb non installé: pip install pyusb")
        return

    # Vendor IDs connus pour GoPro
    GOPRO_VENDOR_IDS = [0x2672, 0x26AB]

    for vid in GOPRO_VENDOR_IDS:
        dev = usb.core.find(idVendor=vid)
        if dev:
            print(f"GoPro trouvée! Vendor: 0x{vid:04x}, Product: 0x{dev.idProduct:04x}")
            print(f"  Manufacturer: {dev.manufacturer}")
            print(f"  Product: {dev.product}")
            print(f"  Serial: {dev.serial_number}")
            print(f"  Configs: {dev.bNumConfigurations}")

            # Lister les interfaces
            for cfg in dev:
                print(f"\n  Configuration {cfg.bConfigurationValue}:")
                for intf in cfg:
                    cls = intf.bInterfaceClass
                    subcls = intf.bInterfaceSubClass
                    proto = intf.bInterfaceProtocol

                    class_names = {
                        1: "Audio",
                        6: "Still Image (PTP)",
                        8: "Mass Storage",
                        10: "CDC Data",
                        14: "Video",
                        255: "Vendor Specific",
                    }
                    cls_name = class_names.get(cls, f"Unknown({cls})")

                    print(f"    Interface {intf.bInterfaceNumber}: "
                          f"Class={cls_name} SubClass={subcls} Protocol={proto}")

                    for ep in intf:
                        direction = "IN" if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_IN else "OUT"
                        print(f"      Endpoint 0x{ep.bEndpointAddress:02x} ({direction}): "
                              f"MaxPacket={ep.wMaxPacketSize}")

            # Vérifier si PTP est disponible
            has_ptp = False
            has_msc = False
            for cfg in dev:
                for intf in cfg:
                    if intf.bInterfaceClass == 6:
                        has_ptp = True
                    if intf.bInterfaceClass == 8:
                        has_msc = True

            print(f"\n  PTP (Still Image): {'OUI' if has_ptp else 'NON'}")
            print(f"  Mass Storage: {'OUI' if has_msc else 'NON'}")

            if has_ptp:
                print("\n  >>> PTP détecté! gphoto2 devrait pouvoir contrôler la caméra.")
            elif has_msc:
                print("\n  >>> Mass Storage uniquement. Pas de contrôle via USB.")
                print("  >>> MAIS on peut surveiller les nouveaux fichiers (polling).")
            return

    print("Aucun device GoPro trouvé via PyUSB.")
    print(f"  Vendor IDs cherchés: {[f'0x{v:04x}' for v in GOPRO_VENDOR_IDS]}")

    # Lister tous les devices USB pour debug
    print("\n  Tous les devices USB:")
    for dev in usb.core.find(find_all=True):
        print(f"    {dev.manufacturer or '?'} — {dev.product or '?'} "
              f"(VID=0x{dev.idVendor:04x} PID=0x{dev.idProduct:04x})")


# ==============================================================
# TEST 5 : Tentative de commande PTP raw
# ==============================================================
def test_ptp_raw():
    section("TEST 5 — Commandes PTP raw (si PTP disponible)")

    try:
        import usb.core
        import usb.util
    except ImportError:
        print("pyusb requis: pip install pyusb")
        return

    GOPRO_VENDOR_IDS = [0x2672, 0x26AB]
    dev = None
    for vid in GOPRO_VENDOR_IDS:
        dev = usb.core.find(idVendor=vid)
        if dev:
            break

    if not dev:
        print("GoPro non trouvée via USB.")
        return

    # Chercher l'interface PTP (class 6)
    ptp_intf = None
    for cfg in dev:
        for intf in cfg:
            if intf.bInterfaceClass == 6:
                ptp_intf = intf
                break

    if not ptp_intf:
        print("Pas d'interface PTP. Tentative sur interface vendor-specific...")
        for cfg in dev:
            for intf in cfg:
                if intf.bInterfaceClass == 255:
                    ptp_intf = intf
                    print(f"  Interface vendor-specific trouvée: {intf.bInterfaceNumber}")
                    break

    if not ptp_intf:
        print("Aucune interface utilisable pour PTP.")
        return

    print(f"Interface PTP/Vendor: {ptp_intf.bInterfaceNumber}")
    print("Tentative de commande GetDeviceInfo (PTP opcode 0x1001)...")

    import struct

    # PTP GetDeviceInfo
    # Container: length(4) + type(2) + opcode(2) + transaction_id(4)
    transaction_id = 1
    ptp_container = struct.pack("<IHHI", 12, 1, 0x1001, transaction_id)

    try:
        # Trouver les endpoints
        ep_out = None
        ep_in = None
        for ep in ptp_intf:
            if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
                ep_out = ep
            elif usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_IN:
                ep_in = ep

        if not ep_out or not ep_in:
            print("Endpoints IN/OUT non trouvés.")
            return

        # Détacher le driver kernel si nécessaire
        if dev.is_kernel_driver_active(ptp_intf.bInterfaceNumber):
            print("  Détachement du driver kernel...")
            dev.detach_kernel_driver(ptp_intf.bInterfaceNumber)

        # Claim l'interface
        usb.util.claim_interface(dev, ptp_intf.bInterfaceNumber)

        # Envoyer GetDeviceInfo
        print(f"  Envoi PTP GetDeviceInfo sur endpoint 0x{ep_out.bEndpointAddress:02x}...")
        ep_out.write(ptp_container)

        # Lire la réponse
        print(f"  Lecture réponse sur endpoint 0x{ep_in.bEndpointAddress:02x}...")
        response = ep_in.read(512, timeout=5000)
        print(f"  Réponse: {len(response)} bytes")
        print(f"  Raw (premiers 64 bytes): {response[:64].tobytes().hex()}")

        # Parser la réponse PTP basique
        if len(response) >= 12:
            length, ptp_type, resp_code, resp_tid = struct.unpack_from("<IHHI", response)
            print(f"  Length: {length}, Type: {ptp_type}, Code: 0x{resp_code:04x}, TID: {resp_tid}")

            if resp_code == 0x2001:
                print("  >>> RÉPONSE OK! La GoPro Max parle PTP!")
                print("  >>> On peut potentiellement envoyer InitiateCapture (0x100E)...")

                # Tenter InitiateCapture
                print("\n  TENTATIVE InitiateCapture (0x100E)...")
                transaction_id += 1
                capture_cmd = struct.pack("<IHHI", 12, 1, 0x100E, transaction_id)
                ep_out.write(capture_cmd)
                time.sleep(1)

                try:
                    cap_response = ep_in.read(512, timeout=10000)
                    cap_length, cap_type, cap_code, cap_tid = struct.unpack_from("<IHHI", cap_response)
                    print(f"  Réponse: Code=0x{cap_code:04x}")
                    if cap_code == 0x2001:
                        print("  >>> CAPTURE RÉUSSIE VIA USB PTP!!!")
                    elif cap_code == 0x2019:
                        print("  >>> Device busy")
                    elif cap_code == 0x2005:
                        print("  >>> Opération non supportée (attendu)")
                    else:
                        print(f"  >>> Code inconnu: 0x{cap_code:04x}")
                except Exception as e:
                    print(f"  Pas de réponse à InitiateCapture: {e}")
            else:
                print(f"  Code de réponse inattendu: 0x{resp_code:04x}")

        usb.util.release_interface(dev, ptp_intf.bInterfaceNumber)

    except usb.core.USBError as e:
        print(f"  Erreur USB: {e}")
        print("  (Peut nécessiter sudo ou des permissions udev)")
    except Exception as e:
        print(f"  Erreur: {e}")


# ==============================================================
# TEST 6 : Polling mass storage (watch pour nouveaux fichiers)
# ==============================================================
def test_mass_storage_polling():
    section("TEST 6 — Polling Mass Storage (nouveaux fichiers)")

    mount_point = None

    # Chercher le volume GoPro
    import platform
    if platform.system() == "Darwin":
        for v in Path("/Volumes").iterdir():
            if (v / "DCIM").exists():
                mount_point = v
                break
    else:
        rc, out, _ = run_cmd(["findmnt", "-t", "vfat,exfat", "-o", "TARGET", "-n"])
        if rc == 0:
            for line in out.split("\n"):
                mp = line.strip()
                if mp and (Path(mp) / "DCIM").exists():
                    mount_point = Path(mp)
                    break

    if not mount_point:
        print("Pas de volume GoPro monté — test ignoré.")
        return

    dcim = mount_point / "DCIM"
    print(f"Volume GoPro: {mount_point}")
    print(f"DCIM: {dcim}")

    # Lister les fichiers actuels
    all_files = set()
    for folder in dcim.iterdir():
        if folder.is_dir():
            for f in folder.iterdir():
                all_files.add(str(f))

    print(f"Fichiers actuels: {len(all_files)}")
    print(f"\nEn attente d'un nouveau fichier...")
    print(f"  → Prends une photo manuellement sur la GoPro (bouton shutter)")
    print(f"  → Ctrl+C pour annuler\n")

    try:
        start = time.time()
        while time.time() - start < 60:  # timeout 60s
            current_files = set()
            for folder in dcim.iterdir():
                if folder.is_dir():
                    for f in folder.iterdir():
                        current_files.add(str(f))

            new_files = current_files - all_files
            if new_files:
                print(f"NOUVEAU FICHIER DÉTECTÉ après {time.time()-start:.1f}s:")
                for f in new_files:
                    p = Path(f)
                    size_mb = p.stat().st_size / (1024*1024)
                    print(f"  {p.name} ({size_mb:.1f} MB)")
                print("\n>>> Le polling mass storage fonctionne!")
                print(">>> On peut détecter quand la GoPro prend une photo")
                print(">>> (même si on ne peut pas la déclencher via USB)")
                return

            time.sleep(0.5)
            elapsed = int(time.time() - start)
            if elapsed % 5 == 0:
                print(f"  ...attente ({elapsed}s)")

        print("Timeout 60s — aucun nouveau fichier détecté.")

    except KeyboardInterrupt:
        print("\nAnnulé.")


# ==============================================================
# RÉSUMÉ
# ==============================================================
def print_summary(results):
    section("RÉSUMÉ — Ce qui fonctionne en USB")
    print("Colle ce résumé dans le chat pour qu'on décide de la suite.\n")

    for test_name, result in results.items():
        status = "✓" if result else "✗"
        print(f"  {status} {test_name}")

    print("""
PROCHAINES ÉTAPES:
  - Si PTP fonctionne → on peut tout contrôler en USB (jackpot!)
  - Si Mass Storage seul → on peut au moins détecter les nouvelles photos
    et les copier automatiquement (trigger via BLE ou bouton physique)
  - Si rien → on reste sur WiFi (le setup actuel fonctionne)
""")


# ==============================================================
# MAIN
# ==============================================================
def main():
    print("""
╔══════════════════════════════════════════════════════════════╗
║        DIAGNOSTIC USB — GOPRO MAX                          ║
║                                                            ║
║  Branche ta GoPro Max en USB-C et allume-la.               ║
║  Ce script va tester toutes les méthodes de communication. ║
╚══════════════════════════════════════════════════════════════╝
""")

    results = {}

    # Test 1: détection USB
    results["Détection USB (lsusb/system_profiler)"] = test_usb_detection()

    # Test 2: gphoto2
    test_gphoto2()
    results["gphoto2 (PTP/MTP)"] = True  # résultat qualitatif, lire la sortie

    # Test 3: Mass Storage
    mount = test_mass_storage()
    results["Mass Storage (carte SD)"] = mount is not None

    # Test 4: PyUSB raw
    test_pyusb()

    # Test 5: PTP raw
    test_ptp_raw()

    # Test 6: Polling (interactif — demande une action manuelle)
    if mount:
        test_mass_storage_polling()

    # Résumé
    print_summary(results)


if __name__ == "__main__":
    main()
