#!/bin/bash
# =============================================================================
# Récupère un scan depuis le Pi, lance KISS-ICP, et ouvre dans CloudCompare
#
# Usage:
#   ./scripts/get_scan.sh 106
#   ./scripts/get_scan.sh cesi3
#   ./scripts/get_scan.sh 106 --raw    # juste le nuage brut, sans KISS-ICP
# =============================================================================

set -euo pipefail

PI="simon@lidar-scanner.local"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$PROJECT_DIR/data/raw"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <scan_name> [--raw]"
    echo ""
    echo "Scans disponibles sur le Pi :"
    ssh "$PI" "ls ~/scans/"
    exit 1
fi

SCAN="$1"
RAW_ONLY="${2:-}"
LOCAL_DIR="$DATA_DIR/$SCAN"
REMOTE_SCAN="~/scans/$SCAN"

mkdir -p "$LOCAL_DIR"

echo "=== Scan: $SCAN ==="

# Vérifier que le scan existe
ssh "$PI" "test -d $REMOTE_SCAN" || { echo "Erreur: $REMOTE_SCAN n'existe pas sur le Pi"; exit 1; }

# Trouver le rosbag
ROSBAG=$(ssh "$PI" "find $REMOTE_SCAN -name 'metadata.yaml' -printf '%h\n' | head -1")
if [ -z "$ROSBAG" ]; then
    echo "Erreur: pas de rosbag trouvé dans $REMOTE_SCAN"
    exit 1
fi
echo "Rosbag: $ROSBAG"

if [ "$RAW_ONLY" = "--raw" ]; then
    # Export brut uniquement
    echo "Export nuage brut..."
    ssh "$PI" "source /opt/ros/jazzy/setup.bash && ~/lidar-scanner/rpi5/.venv/bin/python ~/lidar-scanner/scripts/processing/export_cloud.py $ROSBAG --topic /unilidar/cloud -o $REMOTE_SCAN/cloud_raw.ply"
    echo "Récupération..."
    scp "$PI:$REMOTE_SCAN/cloud_raw.ply" "$LOCAL_DIR/"
    echo "Ouverture dans CloudCompare..."
    open -a CloudCompare "$LOCAL_DIR/cloud_raw.ply"
else
    # KISS-ICP + alignement
    echo "KISS-ICP en cours..."
    ssh "$PI" "source /opt/ros/jazzy/setup.bash && export kiss_icp_out_dir=$REMOTE_SCAN && ~/lidar-scanner/rpi5/.venv/bin/kiss_icp_pipeline --topic /unilidar/cloud $ROSBAG"

    # Trouver les poses
    POSES=$(ssh "$PI" "find $REMOTE_SCAN -name '*_poses.npy' -newer $ROSBAG | head -1")
    if [ -z "$POSES" ]; then
        POSES=$(ssh "$PI" "find $REMOTE_SCAN -path '*/latest/*_poses.npy' | head -1")
    fi

    if [ -z "$POSES" ]; then
        echo "Erreur: poses non trouvées"
        exit 1
    fi
    echo "Poses: $POSES"

    echo "Alignement des scans..."
    ssh "$PI" "source /opt/ros/jazzy/setup.bash && ~/lidar-scanner/rpi5/.venv/bin/python ~/lidar-scanner/scripts/processing/apply_poses.py --bag $ROSBAG --poses $POSES --topic /unilidar/cloud -o $REMOTE_SCAN/cloud_kiss_icp.ply"

    echo "Récupération..."
    scp "$PI:$REMOTE_SCAN/cloud_kiss_icp.ply" "$LOCAL_DIR/"
    # Récupérer aussi le session_log si disponible
    scp "$PI:$REMOTE_SCAN/session_log.json" "$LOCAL_DIR/" 2>/dev/null || true

    echo "Ouverture dans CloudCompare..."
    open -a CloudCompare "$LOCAL_DIR/cloud_kiss_icp.ply"
fi

echo ""
echo "Fichiers dans: $LOCAL_DIR"
ls -lh "$LOCAL_DIR"
