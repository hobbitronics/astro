#!/bin/bash

TOTAL_FRAMES=1
INTERVAL=2
ISO=100
SHUTTER_SPEED=1
APERTURE=11

# 1. Kill background processes to free up the USB interface
echo "Releasing USB lock from system volume monitors..."
systemctl --user stop gvfs-gphoto2-volume-monitor.service 2>/dev/null
killall gvfs-gphoto2-volume-monitor gvfsd-gphoto2 2>/dev/null

# 2. Check if the camera is physically connected and detected
echo "Checking camera connection..."
if ! gphoto2 --auto-detect | grep -q "usb"; then
    echo "❌ ERROR: Camera not detected! Check your USB cable and power switch."
    systemctl --user start gvfs-gphoto2-volume-monitor.service 2>/dev/null
    exit 1
fi
echo "✓ Camera detected successfully."

# 3. Check battery status
echo "Checking battery level..."
BATTERY_INFO=$(gphoto2 --get-config /main/status/batterylevel 2>/dev/null)
BATTERY_VAL=$(echo "$BATTERY_INFO" | grep "Current:" | awk '{print $2}')

if [ -z "$BATTERY_VAL" ]; then
    echo "⚠️ WARNING: Could not read battery level. Proceeding with caution."
else
    echo "✓ Battery level is at: $BATTERY_VAL"
    if [[ "$BATTERY_VAL" =~ ^[0-9]+$ ]] && [ "$BATTERY_VAL" -lt 20 ]; then
        echo "❌ ERROR: Battery is too low ($BATTERY_VAL%). Recharge before starting."
        systemctl --user start gvfs-gphoto2-volume-monitor.service 2>/dev/null
        exit 1
    fi
fi

# 4. Create a uniquely named folder for tonight's session
SESSION_DIR="astro_$(date +%Y-%m-%d_%H-%M)"
echo "Creating session directory: $SESSION_DIR"
mkdir -p "$SESSION_DIR"
cd "$SESSION_DIR" || exit 1

# 5. Set static camera configurations upfront
echo "Configuring camera settings (RAW, ISO $ISO, ${SHUTTER_SPEED}s, f/$APERTURE)..."
gphoto2 \
  --set-config /main/imgsettings/imgformat=RAW \
  --set-config /main/imgsettings/iso="$ISO" \
  --set-config /main/capturesettings/shutterspeed="$SHUTTER_SPEED" \
  --set-config /main/capturesettings/aperture="$APERTURE" > /dev/null 2>&1

# 6. Capture loop with a visual progress bar
echo "Starting capture sequence..."
for ((i=1; i<=TOTAL_FRAMES; i++)); do
    # Calculate progress metrics
    PERCENT=$(( i * 100 / TOTAL_FRAMES ))
    BAR_LENGTH=$(( PERCENT / 4 ))

    # Construct visual bar graphics
    BAR=$(printf "%${BAR_LENGTH}s" | tr ' ' '#')
    SPACES=$(printf "%$((25 - BAR_LENGTH))s")

    # Print the live tracking progress bar line
    printf "\rProgress: [%-25s] %d%% (%d/%d frames)" "$BAR" "$PERCENT" "$i" "$TOTAL_FRAMES"

    # Capture a single frame and name it sequentially
    gphoto2 --filename "astro_shot_$(printf "%03d" "$i").%C" --capture-image-and-download > /dev/null 2>&1

    # Wait for the next interval bracket if it isn't the final frame
    if [ "$i" -lt "$TOTAL_FRAMES" ]; then
        sleep "$INTERVAL"
    fi
done
echo "" # Clean break line after progress bar hits 100%

# 7. Restore system services
echo "🎉 Sequence complete! Restoring system volume monitor..."
systemctl --user start gvfs-gphoto2-volume-monitor.service 2>/dev/null
