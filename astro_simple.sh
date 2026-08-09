#!/bin/bash

echo "Releasing USB lock from system volume monitors..."
systemctl --user stop gvfs-gphoto2-volume-monitor.service 2>/dev/null
killall gvfs-gphoto2-volume-monitor gvfsd-gphoto2 2>/dev/null

SESSION_DIR="astro_$(date +%Y-%m-%d_%H-%M)"
echo "Creating session directory: $SESSION_DIR"
mkdir -p "$SESSION_DIR"
cd "$SESSION_DIR" || exit

echo "Starting sequence: 200 RAW frames at ISO 800, 2s, f/3.5..."
gphoto2 \
  --set-config /main/imgsettings/imgformat=RAW \
  --set-config /main/imgsettings/iso=800 \
  --set-config /main/capturesettings/shutterspeed=2 \
  --set-config /main/capturesettings/aperture=3.5 \
  --filename "astro_shot_%03n.%C" \
  --frames 200 \
  --interval 3 \
  --capture-image-and-download

echo "Sequence complete! Restoring system volume monitor..."
systemctl --user start gvfs-gphoto2-volume-monitor.service 2>/dev/null
