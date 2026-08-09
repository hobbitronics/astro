#!/bin/bash

MONITOR_STOPPED=0

restore_volume_monitor() {
    if [ "$MONITOR_STOPPED" -eq 1 ]; then
        systemctl --user start gvfs-gphoto2-volume-monitor.service 2>/dev/null
        MONITOR_STOPPED=0
    fi
}

trap restore_volume_monitor EXIT

get_config_choices() {
    local config_path="$1"
    local fallback_choices="$2"
    local choices

    choices=$(gphoto2 --get-config "$config_path" 2>/dev/null | awk '
        /^Choice:/ {
            sub(/^Choice:[[:space:]]+[0-9]+[[:space:]]+/, "")
            if (choices != "") choices = choices ", "
            choices = choices $0
        }
        END {
            if (choices != "") print choices
        }
    ')

    if [ -n "$choices" ]; then
        echo "$choices"
    else
        echo "$fallback_choices"
    fi
}

# Ask for capture settings
read -p "Number of frames [1]: " TOTAL_FRAMES
TOTAL_FRAMES=${TOTAL_FRAMES:-1}

read -p "Interval between shots in seconds [12]: " INTERVAL
INTERVAL=${INTERVAL:-12}

echo ""
echo "Capture settings:"
echo "  Frames:       $TOTAL_FRAMES"
echo "  Interval:     ${INTERVAL}s"

# 1. Kill background processes to free up the USB interface

echo ""
echo "Releasing USB lock from system volume monitors..."
systemctl --user stop gvfs-gphoto2-volume-monitor.service 2>/dev/null
killall gvfs-gphoto2-volume-monitor gvfsd-gphoto2 2>/dev/null
MONITOR_STOPPED=1

# 2. Check if the camera is physically connected and detected

echo "Checking camera connection..."
if ! gphoto2 --auto-detect | grep -q "usb"; then
    echo "❌ ERROR: Camera not detected! Check your USB cable and power switch."
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
        exit 1
    fi
fi

SHUTTER_OPTIONS=$(get_config_choices "/main/capturesettings/shutterspeed" "bulb, 1, 1/60, 1/125, 1/250")
APERTURE_OPTIONS=$(get_config_choices "/main/capturesettings/aperture" "3.5, 5.6, 8, 11, 16")
ISO_OPTIONS=$(get_config_choices "/main/imgsettings/iso" "100, 200, 400, 800, 1600")

echo ""
echo "Available ISO options: $ISO_OPTIONS"
read -p "ISO [1600] (enter one of the listed values): " ISO
ISO=${ISO:-1600}

echo ""
echo "Available shutter speed options: $SHUTTER_OPTIONS"
read -p "Shutter speed [10] (enter one of the listed values): " SHUTTER_SPEED
SHUTTER_SPEED=${SHUTTER_SPEED:-10}

echo "Available aperture options: $APERTURE_OPTIONS"
read -p "Aperture [3.5] (enter one of the listed values): " APERTURE
APERTURE=${APERTURE:-3.5}

echo ""
echo "Capture settings:"
echo "  Frames:       $TOTAL_FRAMES"
echo "  Interval:     ${INTERVAL}s"
echo "  ISO:          $ISO"
echo "  Shutter:      $SHUTTER_SPEED"
echo "  Aperture:     $APERTURE"
echo ""

read -p "Start capture? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# 4. Create a uniquely named folder for tonight's session

SESSION_DIR="astro_$(date +%Y-%m-%d_%H-%M)"
echo "Creating session directory: $SESSION_DIR"
mkdir -p "$SESSION_DIR"
cd "$SESSION_DIR" || exit 1

# 5. Set camera configurations

echo "Configuring camera settings..."
gphoto2 \
    --set-config /main/imgsettings/imgformat=RAW \
    --set-config /main/imgsettings/iso="$ISO" \
    --set-config /main/capturesettings/shutterspeed="$SHUTTER_SPEED" \
    --set-config /main/capturesettings/aperture="$APERTURE" \
    > /dev/null 2>&1

# 6. Capture loop with progress bar

echo ""
echo "Starting capture sequence..."

for ((i=1; i<=TOTAL_FRAMES; i++)); do

    # Calculate progress
    PERCENT=$(( i * 100 / TOTAL_FRAMES ))
    BAR_LENGTH=$(( PERCENT / 4 ))

    # Construct progress bar
    BAR=$(printf "%${BAR_LENGTH}s" | tr ' ' '#')

    # Print progress
    printf "\rProgress: [%-25s] %d%% (%d/%d frames)" \
        "$BAR" "$PERCENT" "$i" "$TOTAL_FRAMES"

    # Capture frame
    gphoto2 \
        --filename "astro_shot_$(printf "%03d" "$i").%C" \
        --capture-image-and-download \
        > /dev/null 2>&1

    # Wait for next shot
    if [ "$i" -lt "$TOTAL_FRAMES" ]; then
        sleep "$INTERVAL"
    fi

done

echo ""
echo ""
echo "🎉 Sequence complete!"
echo "Images saved in: $(pwd)"

# 7. Restore system services

echo "Restoring system volume monitor..."
restore_volume_monitor
trap - EXIT
