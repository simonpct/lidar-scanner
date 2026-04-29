# Bootstrap Raspberry Pi 5 depuis le Mac

Deux méthodes pour installer le Pi 5 + projet LiDAR Scanner depuis le Mac.

## Méthode A — Flash direct SSD (recommandé)

Plus rapide et plus simple. Tu sors le SSD du HAT, tu le branches en USB-C sur le Mac, tu flashes, tu remets dans le HAT.

```
Mac                              Pi (boot SSD direct)
───                              ────────────────────
flash_ssd_direct.sh ──►          1. WiFi auto
  - SSD via USB-C                2. git clone repo
  - flash Ubuntu                 3. rpi5/install.sh
  - cloud-init                   4. ROS2, FAST-LIO, dashboard...
```

**Pré-requis :**
- Boîtier USB-C → M.2 NVMe
- Le HAT Geekworm X1001 (où tu remets le SSD ensuite)
- Pi 5 avec firmware EEPROM ≥ 2024-01 (par défaut sur les Pi récents). Sinon voir [section EEPROM](#eeprom) ci-dessous.

**Usage :**
```bash
bash scripts/mac/flash_ssd_direct.sh
```

**Durée totale :** ~10 min de flash + ~30-45 min d'install auto sur le Pi.

---

## Méthode B — Bootstrap via microSD (si pas de boîtier USB-C)

On prépare une SD qui, au 1er boot du Pi, flashe le SSD puis se débranche. Plus de manipulations, plus long.

```
Mac                          Pi (boot SD)               Pi (boot NVMe)
───                          ────────────               ──────────────
prepare_sd_bootstrap.sh ──►  1. WiFi auto         ──►   1. WiFi auto
  - flash Ubuntu sur SD      2. flash NVMe              2. git clone repo
  - cloud-init               3. cloud-init NVMe         3. rpi5/install.sh
  - WiFi + SSH + firstboot   4. EEPROM → NVMe           4. ROS2, FAST-LIO...
                             5. reboot                     dashboard, etc.
```

**Usage :**
```bash
bash scripts/mac/prepare_sd_bootstrap.sh
```

**Durée :** ~45-60 min total (1 GB image téléchargé deux fois si la copie SD ne tient pas en place).

---

## Pré-requis communs (Mac)

- `xz` et `aria2c` (auto-installés via Homebrew si manquants)
- Clé SSH `~/.ssh/id_ed25519.pub` (utilisée pour SSH sans mot de passe sur le Pi)

## Configuration (par défaut, modifiables en haut du script)

- Hostname : `lidar-scanner`
- Utilisateur : `simon` / mot de passe : `simon` + clé SSH
- WiFi : `Freebox-680CF2-IOT` + `Simon`
- HAT : Geekworm X1001 (PCIe Gen 3)

## Suivre l'avancement (les deux méthodes)

```bash
ssh simon@lidar-scanner.local
sudo journalctl -u lidar-install -f
```

Quand c'est fini :
- Dashboard : `http://lidar-scanner.local:8080`
- Foxglove Bridge : `ws://lidar-scanner.local:8765`

---

## Dépannage

### Le Pi ne se connecte pas au WiFi
- Vérifier que la box est à portée
- Brancher écran HDMI + clavier USB pour voir les logs locaux
- Re-flasher en modifiant `WIFI*` dans le script

### EEPROM — le Pi ne boote pas sur le SSD <a id="eeprom"></a>

Sur les Pi 5 anciens, l'EEPROM n'a pas `BOOT_ORDER=0xf416` par défaut. Symptôme : le Pi reste sur LED rouge fixe ou clignotements verts ininterrompus.

**Fix temporaire :** mettre une SD avec Raspberry Pi OS (juste pour booter), puis :
```bash
sudo rpi-eeprom-config --edit
# mettre :
BOOT_ORDER=0xf416
PCIE_PROBE=1
# sauver, retirer la SD, rebooter sans SD
```

Ensuite le Pi bootera toujours sur SSD, plus jamais besoin de SD.

### `lidar-install.service` bloqué
```bash
ssh simon@lidar-scanner.local
sudo journalctl -u lidar-install -f
# pour relancer :
sudo rm /var/lib/lidar-install.done
sudo systemctl start lidar-install
```

### Pas de SSH (WiFi perdu, etc.)
Voir options : Ethernet direct Mac↔Pi avec partage Internet, écran HDMI + clavier, console série UART.

---

## Fichiers

- **`flash_ssd_direct.sh`** — Méthode A (SSD via USB-C). Recommandé.
- **`prepare_sd_bootstrap.sh`** — Méthode B (SD intermédiaire). Fallback.
- **`firstboot_pi_to_nvme.sh`** — Embarqué dans la SD via cloud-init, exécuté au 1er boot du Pi (Méthode B uniquement).
