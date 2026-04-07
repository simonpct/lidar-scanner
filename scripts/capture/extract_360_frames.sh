#!/bin/bash
# Extraction de frames equirectangulaires depuis une vidéo GoPro Max stitchée.
#
# Prérequis:
#   1. Exporter la vidéo .360 en equirectangular MP4 via GoPro Player (macOS)
#   2. brew install ffmpeg
#
# Usage:
#   ./extract_360_frames.sh video_stitched.mp4 output_dir/ [fps]
#   ./extract_360_frames.sh video_stitched.mp4 output_dir/ 0.5  # 1 frame toutes les 2 sec

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <video_stitched.mp4> <output_dir/> [fps=1]"
    echo ""
    echo "  fps=1   -> 1 frame par seconde"
    echo "  fps=0.5 -> 1 frame toutes les 2 secondes"
    echo "  fps=2   -> 2 frames par seconde"
    exit 1
fi

VIDEO="$1"
OUTPUT_DIR="$2"
FPS="${3:-1}"

mkdir -p "$OUTPUT_DIR"

echo "Extraction des frames depuis: $VIDEO"
echo "  FPS: $FPS"
echo "  Sortie: $OUTPUT_DIR/"

ffmpeg -i "$VIDEO" \
    -vf "fps=$FPS" \
    -q:v 2 \
    "$OUTPUT_DIR/frame_%04d.jpg"

COUNT=$(ls -1 "$OUTPUT_DIR"/frame_*.jpg 2>/dev/null | wc -l)
echo "Terminé! $COUNT frames extraites dans $OUTPUT_DIR/"
